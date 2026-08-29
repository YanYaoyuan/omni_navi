# 机器人运行时模块详解

> 审计基线：2026-08-28 当前工作区
>
> 范围：`omni_robot_interfaces`、`omni_tf_manager`、`omni_slam`、`omni_planner`、`omni_robot_bridge`、`omni_docking`、`omni_mission_manager`
>
> 说明：本页描述**当前代码如何工作**。需要新增或修改的内容明确标为“目标/缺口”，不与现状混写。

## 1. 七个模块如何分工

| 层 | 模块 | 只负责什么 | 明确不负责什么 |
| --- | --- | --- | --- |
| 合同 | `omni_robot_interfaces` | 跨仓产品 msg/srv/action 和稳定枚举 | 不运行节点、不管理状态 |
| 坐标 | `omni_tf_manager` | canonical TF、外参、传感器别名、标准 body odom、TF ready | 不启动 SLAM、不管理地图 |
| 状态估计 | `omni_slam` | FAST-LIO、ICP 重定位、进程监督、地图版本和 SLAM 状态 | 不发布受管 TF、不控制底盘 |
| 路径执行 | `omni_planner` | 局部占据图、重规划、轨迹优化/验收、闭环跟踪、FollowRoute | 不持有最终速度出口、不编排巡检业务 |
| 底盘安全 | `omni_robot_bridge` | 唯一 SDK owner、速度仲裁、E-stop、限幅、状态聚合 | 不规划路线、不执行任务 |
| 末端回充 | `omni_docking` | Dock/Undock 末端几何控制和充电确认 | 不做全局路径规划、不拥有地图 |
| 任务编排 | `omni_mission_manager` | 任务生命周期、路线/检查点、持久化、返航两段式编排 | 不直接发布速度、不调用厂商 SDK |

理想调用方向是单向的：

```text
Mission ──Action──> Planner ──candidate cmd──> Bridge ──SDK──> Robot
   │                                      ▲
   ├────Action──> Docking ────────────────┘
   └────Service──> Inspection providers（当前缺失）

Sensors ──> SLAM ──pose/alignment/status──> TF Manager ──TF/odom/ready──> Planner
                                      └───────────────────────────────> Bridge/Mission
```

当前最大断点是 Mission 请求 typed authority，而 Bridge 只实现旧字符串租约；因此单个模块能运行并不等于上述链路能闭环。

## 2. `omni_robot_interfaces`：跨仓产品合同

### 2.1 模块形态

仓库是纯 `rosidl` 包，没有运行进程。所有 Action 的 Goal/Result/Feedback 顺序和常量值由 CI 检查，V1 采用“只加字段/类型，不修改既有常量语义”的兼容策略。

当前包含：

- 5 个消息：`RobotState`、`MissionStatus`、`MissionEvent`、`CheckpointResult`、`DockStatus`；
- 10 个服务：任务派发/控制/查询、控制权、路线、巡检载荷、Dock 配置/充电查询；
- 5 个动作：`ExecuteInspection`、`FollowRoute`、`ReturnToDock`、`Dock`、`Undock`。

### 2.2 状态消息

#### `RobotState`

Bridge 是预期唯一生产者，内容合并五个维度：

1. `operational_mode`：IDLE、MAPPING、LOCALIZING、MISSION、DOCKING、ESTOP；
2. `control_authority`：NONE、APP、MISSION、DOCKING，外加 client ID 和剩余租期；
3. localization：UNKNOWN、DEGRADED、LOST、LOCALIZED，以及 map identity/fitness；
4. health/safety：健康等级、摘要、E-stop、`motion_authorized`；
5. mission/power：任务快照、电压、电量、充电。

当前 `motion_authorized` 的 IDL 注释和 Bridge 实现都只等价于“未急停且存在租约”，它不是完整的安全运动许可。TF、定位 freshness、命令来源和硬件连接仍需进入 V2 合同。

#### `MissionStatus` 与 `MissionEvent`

`MissionStatus` 是单活动任务的最后快照，使用 Reliable + Transient Local；`MissionEvent` 是状态迁移的实时追加流，持久历史在 Mission SQLite 中。两者的任务状态数值必须与 `RobotState.MISSION_*` 保持一致。

#### `CheckpointResult`

每个 photo/record/recognize 动作完成后产生一条记录，包含 mission/checkpoint/action、尝试次数、结果、artifact path/result JSON、执行位姿、地图和软件版本。`dwell` 只是时间行为，不产生证据记录。

#### `DockStatus`

是 Docking 自己的状态视图，不包含全局导航腿。ReturnToDock feedback 是 Mission 对整条“导航→末端→充电”链的视图，两者不能互相替代。

### 2.3 幂等语义

任务派发使用 `(request_id, sequence)`：

- 相同 pair 重放：返回原始结果，不重复物理动作；
- 同一 request_id 的更高 sequence：表示新尝试；
- request_id 不是日志字段，而是安全合同的一部分。

Planner 使用每进程 epoch 内的 `mission_id` 去重；ReturnToDock/Dock/Undock 也各自使用 request identity。这些去重域不同，Mission 必须负责生成稳定、可追踪的下游 identity。

### 2.4 当前所有权泄漏

- `SlamStatus.msg` 位于 `omni_tf_manager`，但语义和生产者属于 SLAM；
- 建图/定位操作位于 `omni_slam_interfaces`；
- Planner 内部心跳/B-spline 正确保留在 `scan_planner_msgs`，不需要迁入产品合同仓；
- VBot 消息属于供应商接口，不能复制进产品合同仓。

目标是在 V2 将跨仓 SLAM 类型收敛到 `omni_robot_interfaces`，同时保留一次明确的兼容迁移窗口。

## 3. `omni_tf_manager`：坐标系和传感器归一化

### 3.1 进程与配置

- 包/可执行：`omni_tf_manager` / `omni_tf_manager_node`；
- 默认节点名：`/omni_tf_manager`；
- 核心配置：robot profile YAML；
- profile 描述 frame 名、完整 6DoF 外参、传感器原始 Topic/frame、canonical alias、authority/shadow 模式和 freshness/jump 阈值。

Profile 是标定事实源。SLAM launch、Planner launch 和 URDF 不应各自再写一套相互冲突的 LiDAR/IMU/Camera 外参。

### 3.2 输入、计算和输出

主要输入：

- `/state_estimation`：FAST-LIO 的 tracking-frame 局部位姿；
- `/icp_result`：ICP 输出的 `T_map_icp_sensor`；
- `/omni/slam/status`：SLAM 模式和健康状态；
- 厂商点云、IMU、camera 的原始 Topic。

关键变换：

```text
T_odom_base = T_odom_tracking × inverse(T_base_tracking)

T_map_odom = T_map_icp_sensor × inverse(T_tracking_icp_sensor)
```

第二式中的 tracking→ICP sensor 来自当前局部估计与已审核静态外参。建图模式使用 identity `map→odom`；定位模式必须先接收并接受 ICP alignment。

输出包括：

- `/tf_static`：base、IMU、LiDAR、camera 等固定边；
- `/tf`：`map→odom`、`odom→base`；
- local/global body odometry；
- `/omni/tf_manager/ready`；
- `/diagnostics`；
- `/omni/sensors/*` canonical 传感器 alias。

### 3.3 authority 与 shadow

- **authority**：发布受管 TF、canonical 数据和主 ready；
- **shadow**：只做候选计算/诊断，用于迁移比对，不得与另一 authority 竞争同一 TF child。

当前代码/profile 有一处文档漂移：`omni_vbot_dog.yaml` 实际为 authority，而部分旧文档仍称 Dog/VBot 是 shadow。上线判断必须读部署所用 YAML，不能读旧说明猜测。

### 3.4 Alias 的真实含义

Alias 路径目前只校验和重写消息 metadata，不会旋转/平移点云或 IMU 数值。因此只有当“原始 frame 与 canonical frame 物理完全相同，只是命名不同”时才安全。存在真实外参差异时必须做坐标变换，单改 `header.frame_id` 会制造错误数据。

Authority profile 对未验证 alias 采取拒绝策略；这是一项正确的 fail-closed 设计。

### 3.5 ready 当前语义与缺口

当前 ready 检查：

- profile/mode 有效；
- sensor odometry 新鲜；
- 定位模式已取得 map alignment；
- 所需 TF/输入未超时。

但它没有严格检查 `SlamStatus.initialized=true`，也没有把所有 state（DEGRADED/LOST/STOPPING/ERROR）映射成 false。目标语义应是：authority、fresh status、合法 mode/state、initialized、fresh odom、定位时 fresh/accepted alignment 全部成立才 ready。

### 3.6 防御机制

- frame ID 和时间戳校验；
- quaternion 有限性和归一化；
- 平移/旋转 jump 阈值；
- ICP alignment 默认只接受一次，除非显式 reinitialize；
- diagnostics 解释拒绝原因；
- authority 下不允许未经审核的外参/alias。

## 4. `omni_slam`：建图、重定位和地图资产

### 4.1 四层结构

| 子包 | 语言 | 职责 |
| --- | --- | --- |
| `fast_lio` | C++ | LiDAR/IMU 紧耦合局部状态估计和点云地图 |
| `icp_relocalization` | C++ | 先验地图加载、ICP 对齐、注册点云发布 |
| `omni_slam_interfaces` | ROS IDL | Start/Stop Mapping、SaveMap、Start/Stop Localization |
| `omni_slam_manager` | Python | 子进程监督、状态机、遥测 freshness、地图版本存储 |

`dist/omni_slam` 是生成的发布拷贝，不是第二套源码；`.github/ci/livox_stub` 只是 CI 依赖桩。

### 4.2 FAST-LIO 数据面

`fastlio_mapping` 订阅 canonical LiDAR/IMU，执行预处理、IMU propagation、点到平面更新和增量 ikd-tree 地图维护，输出：

- `/state_estimation`：局部 `odom→tracking` 位姿；
- 局部/全量配准点云；
- 建图保存服务所需地图数据。

Omni 修改重点：

- 关闭自身 TF 发布，把 TF authority 交给 TF Manager；
- 定位 profile 要求先验 PCD；
- 接收 ICP 初始对齐；
- 配置区分 Matrix、Dog/VBot、不同 LiDAR；
- 主处理周期约 100 Hz，传感器 Topic/QoS 必须端到端匹配。

### 4.3 ICP 重定位

`icp_node`：

1. 加载先验 PCD；
2. 体素降采样；
3. 接收当前局部点云/初始 guess；
4. 执行 ICP；
5. 检查 convergence、fitness 和连续成功次数；
6. 发布 `/icp_result`，表达 `T_map_sensor`；
7. 达到确认条件后退出其节点。

`global_pointcloud_publisher` 将已配准当前点云变换到 map frame 供 Planner/可视化使用。`sac_ia_gicp` 是更重的可选粗配准/研究入口，不属于默认产品链。

### 4.4 SLAM Manager 状态机

管理器使用 `MultiThreadedExecutor(4)`，自身不做点云算法，而是启动/停止整个子进程组。核心状态语义：

```text
STOPPED
  ├─ start_mapping ─> STARTING ─> MAPPING ─> MAP_READY
  └─ start_localization ─> STARTING ─> LOCALIZING ─> LOCALIZED

任意活动态 ── stop ─> STOPPING ─> STOPPED
子进程退出/遥测失败 ─> ERROR 或 DEGRADED/LOST
```

具体状态常量以 `SlamStatus` 为准。管理器周期发布 status heartbeat；`initialized` 只在相应运行态且遥测 fresh 时为真。定位只有在先验地图验证、子进程启动、FAST-LIO 遥测新鲜并观察到 ICP 初始化后才进入 LOCALIZED。

### 4.5 子进程监督

- 每个算法 launch 作为独立 process group 启动；
- stop 先给进程组温和信号，超时再升级；
- 非预期子进程退出进入 ERROR；
- Action cancel 需要停止正在进行的启动/保存流程；
- manager 退出时清理子进程，避免遗留第二套发布者。

进程存在只代表算法进程活着；manager 还使用点云、IMU、odom freshness 判断真正健康。

### 4.6 地图存储

默认逻辑是不可变版本：

```text
<map_root>/<map_id>/
├── versions/
│   └── v<version>/
│       ├── map.pcd
│       └── metadata.json
└── current -> versions/v<version>
```

保存流程调用 FAST-LIO `/map_save`，在 staging 中验证文件、计算 SHA256、写 metadata，然后原子激活版本/`current` 链接。定位前重新验证 map identity/hash，不能只信文件名。

## 5. `omni_planner`：局部规划、轨迹执行和速度控制

### 5.1 六个产品包

| 包 | 核心职责 |
| --- | --- |
| `plan_env` | 滑动概率占据栅格、raycast、增量膨胀、机器人双圆柱碰撞查询 |
| `path_searching` | projected A* 等局部无碰搜索 |
| `bspline_opt` | B-spline 反弹优化、平滑/碰撞/动力学/参考路径代价 |
| `traj_utils` | 多项式/B-spline 轨迹工具和可视化 |
| `scan_planner_msgs` | B-spline、Planner heartbeat 等内部合同 |
| `scan_planner` | FSM、Planner Manager、FollowRoute server、closed-loop controller |

### 5.2 环境模型

地图是机器人周围的滑动三维概率栅格：

1. depth/point cloud 投入 raycast；
2. 射线空闲单元递减 log-odds，端点递增；
3. 只更新变化区域；
4. occupied cell 增量膨胀；
5. 以机器人上下双圆柱和路径切向 yaw 做碰撞查询。

这不是 SLAM 的持久地图所有者。它消费全局/局部点云并构造规划窗口，重启后可以重建。

### 5.3 三种目标模式

- 模式 1：手工目标点；
- 模式 2：预设 waypoint；
- 模式 3：外部 reference route，产品 Mission/FollowRoute 使用此模式。

全局路线进入后，Planner 根据当前位置和局部规划距离选择 local target，不会一次优化整条长路线。

### 5.4 规划管线

```text
reference route / goal
  -> local target
  -> minimum-snap / initial B-spline
  -> collision check
  -> projected A* 绕障（需要时）
  -> rebound constraints
  -> L-BFGS 优化
  -> time re-allocation
  -> bounded final acceptance validation
  -> 发布 B-spline + heartbeat
```

优化代价至少包含 smoothness、collision、feasibility 和 reference-route adherence。优化“返回成功”并不直接放行；最终 validator 还检查：

- 所有控制点和导数有限；
- 速度/加速度约束；
- 时间和空间采样资源上限；
- 双圆柱在全采样轨迹上无碰撞。

Validator 超时、NaN 或资源预算耗尽都拒绝轨迹。

### 5.5 Planner FSM

```text
INIT -> WAIT_TARGET -> GEN_NEW_TRAJ -> EXEC_TRAJ
                         ^                |
                         └─ REPLAN_TRAJ <-┘
任意运动态 -> EMERGENCY_STOP -> WAIT_TARGET/重置
```

执行 timer 约 100 Hz，安全检查约 20 Hz，heartbeat 约 20 Hz。输入包括 body pose、sensor pose/point cloud、TF ready、目标/路径和 execution-frozen 信号。

### 5.6 `FollowRoute` Action

- 只接受 reference path 模式；
- 单活动 route；
- 每个 Planner 进程 epoch 内按 `mission_id` 去重；
- goal gate 检查 odom、path、frame/map、speed scale；
- feedback 提供沿路线的空间进度，不以轨迹时间冒充任务进度；
- cancel 执行受控停车并返回 USER_CANCELED；
- terminal monitor 检测 localization/heartbeat/timeout/stuck 等失败。

Mission 将检查点路线拆成多段时，会为每段生成 `<mission>-s<index>-a<attempt>` 形式的 Planner goal identity，原始 mission/request identity仍被保留用于审计。

### 5.7 Planner heartbeat 与轨迹 identity

Planner 发布 transient local 的 B-spline，并以 volatile heartbeat 周期发送：

- trajectory ID；
- start time；
- 当前空间进度；
- `motion_allowed`/execution 状态。

Controller 只有在 heartbeat fresh 且 ID/start time 与缓存轨迹完全一致时才执行。这样可防止 Planner 重启后，Controller 继续追踪上个 epoch 的 latched 旧轨迹。

### 5.8 Closed-loop controller

默认约 50 Hz：

1. 接收/校验轨迹和 Planner heartbeat；
2. 用实际 odom 投影到 path，而不是只按 wall-clock 取样；
3. 默认 Pure Pursuit 计算线速度和 yaw；
4. 起步方向偏差大时先 alignment freeze；
5. 对线/角速度做限幅、slew、deadband 和 yaw hysteresis；
6. odom/heartbeat/trajectory 任一过期立即发零。

产品输出当前仍为 `/scan_planner/cmd_vel` 的 `Twist`，由 Bridge 作为 navigation candidate 消费。目标迁移名是 `/omni/cmd_vel/navigation`，但在两端同时改完前不能单边切换。

### 5.9 配置边界

- planner 最大速度与 controller 最大速度是两层限制，默认 controller 更保守（约 0.3 m/s）；
- yaml 的 `require_tf_ready` 可能为 false，但产品 launch 会覆盖，评审必须看最终 launch 参数；
- `zsibot_cmd_bridge`、UDP client、开环 controller 和 simulator 必须显式 opt-in；
- S100 产品构建用包白名单排除仿真和旧直连桥。

## 6. `omni_robot_bridge`：唯一运动和厂商边界

### 6.1 进程与兼容命名

仓库已更名为 `omni_robot_bridge`，但为部署兼容保留：

- ROS 包：`rosdeck_robot_bridge`；
- 节点：`/rosdeck_robot_bridge`、`/rosdeck_safety_supervisor`；
- 可执行：`rosdeck_robot_bridge_node`、`rosdeck_safety_supervisor_node`。

新架构文档使用“Bridge/Safety”指代职责，不以旧命名推断所有权仍属于 App。

### 6.2 Adapter 层

#### ZsiBot

- CMake 显式选择 `zsl-1` 或 `zsl-1w` 及 aarch64/x86_64 ABI；
- Bridge 持有跨进程 SDK owner lock；
- SDK 启停、速度、姿态/步态、BMS/状态读取集中在 adapter；
- 退出和故障路径带 stop 重试。

#### VBot

- 使用 `function_msgs/SetRunMode` 与 `software_msgs/LowlevelAction`；
- 只有在上游接口包存在且 build option 开启时编译；
- 闭源 VBot runtime 由目标机器提供，不在 `vbot_ros2_msgs` 中。

#### Null/simulation

用于 x86 合同构建或无硬件环境，不应在真机 profile 中被静默当作成功硬件。

### 6.3 速度仲裁

Arbiter 维护三个 candidate source：

| authority owner | 唯一速度源 | 典型生产者 |
| --- | --- | --- |
| APP | teleop | Rosdeck/Foxglove 本地入口 |
| MISSION | navigation | Planner controller |
| DOCKING | docking | Docking controller |

当前 ZsiBot profile：

- teleop：`/omni/cmd_vel/teleop`，`TwistStamped`；
- navigation：`/scan_planner/cmd_vel`，`Twist`；
- docking：`/omni/cmd_vel/docking`，`Twist`；
- final：`/omni/cmd_vel/final`，Bridge 内部/adapter 消费。

接收时间 watchdog 默认约 250 ms。每个 candidate 做有限数、stamp、速度范围、publisher conflict 等校验；来源和 owner 不匹配时不输出。默认限幅约为前进 0.6、后退 0.3、横移 0.3 m/s、yaw 0.8 rad/s，最终以部署 YAML 为准。

### 6.4 当前租约协议

Bridge 当前实现的是 legacy String：

```text
/rosdeck/control_command: acquire:<client> | heartbeat:<client> | release:<client>
/rosdeck/control_status : acquired:<client> | holding:<client> | ...
```

租期默认 5 s。owner kind 从 client ID 前缀推断，再映射到速度源。typed `/omni/control/authority` 已在 IDL 和 Mission client 中存在，但 Bridge 没有 provider，这是当前整链 P0 阻塞项。

Typed V2 还需要 lease token/epoch、明确 renew、expiry、preemption reason、release acknowledgement，防止旧 heartbeat 对新租约产生 ABA 影响。

### 6.5 Safety Supervisor

- 独立节点订阅唯一 E-stop heartbeat/硬件安全输入；
- 启动时 latched 且 unarmed；
- 必须先 arm supervisor，再 reset Bridge latch；
- heartbeat 过期、publisher 数量不为一、硬件输入或显式 stop 都 fail-closed；
- child critical exit 会让 `bridge.launch.py` 关闭整组，避免只剩无监督 Bridge。

安全链要求一个正式 E-stop publisher 和一个最终速度 owner。进程 alive 或 topic 存在不能代替 freshness。

### 6.6 RobotState 聚合

聚合器消费 MissionStatus、SlamStatus、battery、租约和 adapter 状态：

- operational mode 优先级大致为 ESTOP > MAPPING > MISSION > DOCKING > LOCALIZING > IDLE；
- localization 只在 localization mode 下映射 fresh SlamStatus；
- health 汇总 adapter、输入 freshness 和告警；
- battery 来自 adapter/sysfs/SDK；
- `motion_authorized = !estop && authority != NONE`。

最后一式过弱。正确的最终许可还要包含 adapter connected、safety heartbeat、source freshness、TF ready、自动模式 localization ready 和 Docking 专属安全 gate。

### 6.7 部署和升级

- systemd 单元使用 `Restart=always`、`KillMode=control-group`、runtime lock dir 和资源限制；
- `run-prebuilt` 指向当前 release 并启动 `product_bringup.launch.py`；
- release 目录为 `<prefix>/releases/<release-id>`；
- `current`/`previous` symlink 原子切换；
- 安装后 health check 失败自动回滚；
- bundle 可带 SHA/signature/SBOM sidecar；
- 默认安装根：VBot `/userdata/rosdeck`，ZsiBot `/opt/rosdeck`。

当前 `product_bringup.launch.py` 只启动 Bridge、Safety 和可选 OpenNav Docking，不包含 TF、SLAM、Planner、自研 Docking、Mission、Edge。这是“发布机制存在但整机组合尚不存在”的准确边界。

## 7. `omni_docking`：末端进桩、出桩和充电确认

### 7.1 进程和数据

- 包/节点：`omni_docking` / `/omni_docking`；
- 输入：`RobotState`、global body pose/odom、`BatteryState`、legacy control status；
- 输出：`/omni/cmd_vel/docking`、`DockStatus`、legacy lease command；
- 服务/动作：Dock、Undock、GetDockConfig、VerifyCharge；
- 控制周期：默认 20 Hz；
- 默认 Dock 根：`/var/lib/omni/docks`。

Dock JSON 绑定 map ID/version、dock ID、final pose 和 approach distance。当前 frame 默认仍为 `lio_map`。

### 7.2 Dock 几何

配置 final pose 表示充电位置和朝向。standoff 是沿 dock 朝向轴反向偏移 `approach_distance`：

```text
standoff.x = dock.x - approach_distance × cos(dock.yaw)
standoff.y = dock.y - approach_distance × sin(dock.yaw)
standoff.yaw = dock.yaw
```

控制器将 global pose 转成 dock 局部轴误差：前后、横向、heading。朝向误差大时先旋转；靠近 final band 后降速；横向误差会进一步降线速度，避免高速斜插。

### 7.3 Dock 状态链

```text
gate
 -> acquire legacy DOCKING lease
 -> SERVING（末端位姿闭环）
 -> WAITING_CHARGE
 -> success / CHARGE_NOT_CONFIRMED / abort
 -> zero + release（所有 terminal path）
```

默认 gate 检查：

- 无另一 Dock/Undock；
- RobotState 新鲜（约 2 s）；
- 未 E-stop；
- localization 为 LOCALIZED；
- map/version 存在匹配 Dock；
- pose 可用且新鲜；
- 已在 standoff 邻域。

Pose 缺失约 0.5 s 开始 gate，运行中超过约 1 s abort。接近默认 45 s 超时，充电确认约 30 s。

### 7.4 充电判定

`ChargeMonitor` 优先级：

1. BatteryState 明确 `CHARGING`/`FULL`；
2. 若状态 unknown，再按配置后的电流方向和阈值；
3. 电流无效时可退到 power；
4. 样本过期一律“不确认”。

到达 pose 但没有 BMS 充电证据，结果为 `CHARGE_NOT_CONFIRMED`，不会把“物理看起来已入桩”当成功。

### 7.5 Undock

Undock 要求位于 dock pose，获得 DOCKING lease 后沿 approach axis 反向低速移动，达到 clearance/standoff 后零速释放。它不调用 Planner，因为这是短距离受控末端行为。

### 7.6 当前实现风险

- 使用 legacy String 租约，不是 typed authority；
- 仅基于 global pose 逼近，尚无真机末端相对视觉/红外/AprilTag、触点等 provider；
- frame/map 不一致的部分路径仍偏向 warning，产品应拒绝；
- ROS Action callback 中把 `goal_handle.is_cancel_requested` 当函数调用，而 rclpy 是属性，可能在运行路径触发 `TypeError`；
- goal 会先被接受，再在执行阶段因 gate abort，客户端得到的是“accepted then aborted”而不是早期 reject。

纯逻辑状态机覆盖充分，但这些 ROS 接线和真机感知缺口意味着当前 Python 节点不能作为“已验证自动回充”证明。

## 8. `omni_mission_manager`：任务、检查点和返航编排

### 8.1 进程和接口

- 包/节点：`omni_mission_manager` / `/omni_mission_manager`；
- provider：ExecuteInspection、DispatchMission、MissionControl、ListRoutes、GetCheckpointResults、ReturnToDock；
- client：FollowRoute、Dock、GetDockConfig、ControlAuthority、CapturePhoto、StartRecord、Recognize；
- input：RobotState、当前 pose、Planner/Docking feedback；
- output：MissionStatus、MissionEvent、CheckpointResult；
- persistence：SQLite event/idempotency/checkpoint store。

节点约 2000 行，纯行为模块与 ROS wiring 分离。默认 `rclpy.spin`，checkpoint 使用 worker thread。

### 8.2 RouteStore

路线主体是已有录线工具产生的 `.txt`：header 后跟点坐标；同名 `.route.json` 可绑定：

- schema version；
- map ID/version；
- frame ID；
- created_at/identity metadata。

Store 对 route ID 做语法/目录穿越防护，拒绝非有限点和少于两个点的路线。无 sidecar 的旧路线可以列出但 map binding 为空；正式任务 gate 应要求资产绑定。

### 8.3 检查点 sidecar

同一路线可带 checkpoint JSON：每个 checkpoint 指向 route point index，并列出动作：

- `dwell`：暂停指定毫秒；
- `photo`：1..20 张；
- `record`：有界秒数；
- `recognize`：有界 target 字符串；
- 每项可配置 attempts 和 `on_failure=skip|fail`。

解析器拒绝未知 action、重复 ID、越界 point、非法 schema 和超限参数。客户端给 `checkpoint_ids` 时只执行选中的集合，未知 ID 拒绝任务。

### 8.4 分段执行

Mission 不把检查点逻辑塞进 Planner。它把 route 切成：

```text
移动 leg 0 -> checkpoint A -> 移动 leg 1 -> checkpoint B -> ...
```

相同点上的多个 checkpoint 可以连续运行；路线起点 checkpoint 会产生零长度首段并就地执行；末点 checkpoint 后不生成多余移动腿。整体进度将各段空间进度映射到全 route，比单纯按段数平均更稳定。

### 8.5 CheckpointRunner

Runner 在 worker thread 中串行动作：

- pause 时 dwell 计时停止，resume 后继续；
- evidence 失败按 attempts 重试；
- pause 不消耗重试次数；
- cancel/abort 立即跳过剩余项；
- 每个 evidence action 终态持久化并发布 `CheckpointResult`；
- recognize JSON 原样存储，Mission 不理解供应商结果结构。

当前 photo/record/recognize 服务只有 client，没有产品 provider，所以路线导航即使成功，也不能完成真实证据闭环。

### 8.6 Mission 状态机和持久化

```text
NONE -> PENDING -> EXECUTING <-> PAUSED
                       ├-> SUCCEEDED
                       ├-> FAILED
                       ├-> CANCELED
                       └-> INTERRUPTED
```

EventStore 将状态快照、事件和 idempotency 结果写入 SQLite。启动恢复发现未完成任务时标为 INTERRUPTED，不自动恢复运动；这是安全优先的正确策略。

派发 gate：

- 单活动任务；
- route/checkpoint 合法；
- RobotState 新鲜且 LOCALIZED；
- map ID/version 匹配；
- Planner action server ready；
- 成功获取 MISSION authority。

Pause 会 cancel 当前 Planner leg 并释放租约；Resume 重新获取租约并以新 attempt identity 继续。Cancel 同样等待下游终止后释放。

### 8.7 ReturnToDock 两段式编排

ReturnToDock 不是普通 inspection Mission，不写 MissionEvent：

1. 从 Docking 查询当前 map 的 final pose/approach distance；
2. 计算 standoff；
3. 以当前位置和 standoff 合成短 `nav_msgs/Path`；
4. MISSION lease 下调用 FollowRoute；
5. Planner 停止后释放 MISSION lease；
6. 调 Dock action，由 Docking 自己申请 DOCKING lease；
7. 等待末端和充电结果。

反馈权重大致为 global navigation 60%、final approach 30%、charge verify 10%。低电触发可中断活动 mission；用户手动返航遇到活动 mission 则拒绝，要求先明确取消。

### 8.8 当前 ROS wiring 阻塞

- Bridge 没有 `/omni/control/authority` provider，派发 gate 无法在现栈成功；
- `_call_authority` 和 Dock config 等等待路径调用 `future.wait_for_future(...)`，不是 rclpy Future API；
- ExecuteInspection/ReturnToDock callback 使用 `goal_handle.goal`，rclpy 正确字段是 `goal_handle.request`；
- `rclpy.spin`、Action execute callback、同步等待与 worker thread 的组合需要节点级测试证明不会饿死回调；
- 节点级 Action 测试不足，现有 208 个通过项主要验证纯行为层。

因此当前代码最准确的定位是“行为定义完整的 Python 原型”，不是已经跑通的生产 ROS Action server。

## 9. 跨模块关键闭环

### 9.1 建图

```text
Operator/bringup -> SLAM Manager StartMapping
 -> FAST-LIO process group
 -> /state_estimation + point cloud
 -> TF Manager publishes odom/base and identity map/odom
 -> SaveMap calls /map_save
 -> immutable map version + hash + current symlink
```

Bridge 此时 RobotState mode 可显示 MAPPING，但 motion authority 和 mapping 手动移动策略仍需统一产品合同。

### 9.2 定位后导航

```text
StartLocalization(map id/version)
 -> verify map hash
 -> ICP + FAST-LIO
 -> ICP alignment accepted
 -> SlamStatus LOCALIZED/initialized/fresh
 -> TF Manager ready
 -> Mission gate
 -> FollowRoute
 -> Planner heartbeat + B-spline
 -> Closed-loop navigation candidate
 -> Bridge owner/source/freshness/safety gates
 -> vendor SDK
```

其中 typed authority provider、严格 TF ready 和统一 bringup 尚未完成，所以这是目标闭环与部分现状的组合，不能声称当前一键可用。

### 9.3 返航

全局 Planner 和末端 Docking 不能同时持有控制权。正确交接：

```text
Planner cancel/success -> navigation zero confirmed
 -> release MISSION -> owner NONE/ack
 -> Docking acquire DOCKING
 -> docking candidate -> pose/contact/charge confirmation
 -> zero -> release DOCKING
```

现有 String status 没有 token/epoch/release ack，暂时无法严格证明这一交接不会被旧 heartbeat 干扰。

## 10. 运行时不变量

1. Bridge 是唯一 SDK owner 和最终速度出口。
2. 每个 candidate Topic 只有一个正式 publisher。
3. TF Manager 是受管 TF child 的唯一 authority。
4. Mission、Planner、Docking 不直接调用厂商服务。
5. 租约有效不等于允许运动。
6. TF、SLAM、command、safety 任一 freshness 未知都输出零。
7. 旧轨迹、旧 command、旧 lease heartbeat 在新进程 epoch 不得复用。
8. 地图、路线、Dock、外参按 identity/hash 绑定，不只按名字。
9. Mission 恢复只恢复审计状态，不自动恢复物理动作。
10. 到达 Dock pose 不等于充电成功。

## 11. 优先级最高的实现缺口

| 优先级 | 缺口 | 受影响链路 |
| --- | --- | --- |
| P0 | Bridge 实现 typed `ControlAuthority`，统一 App/Mission/Docking 租约 | 所有自动运动 |
| P0 | 修复 Mission rclpy Future/goal handle 接线并做节点级 Action 测试 | 任务、返航 |
| P0 | 修复 Docking cancel 属性调用并做节点级测试 | Dock/Undock |
| P0 | TF ready 纳入 SlamStatus initialized/state/freshness | 自动导航许可 |
| P0 | `omni_navi` 增加完整 bringup/preflight/shutdown | 整机部署 |
| P1 | 真机 Dock 相对观测、接触和 BMS 多证据 provider | 自动回充 |
| P1 | photo/record/recognize provider 和证据落盘/outbox | 真实巡检 |
| P1 | `/scan_planner/cmd_vel` 迁移到 canonical navigation candidate | 接口收敛 |
| P1 | SLAM 合同迁入 `omni_robot_interfaces` | 接口所有权 |

跨模块 Topic/Service/Action 的逐项所有者和状态见 [INTERFACE_MATRIX.md](INTERFACE_MATRIX.md)。
