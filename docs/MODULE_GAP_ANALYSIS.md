# Omni 全栈模块缺失与补齐分析

> 文档状态：源码逐模块审计版 v1.0
>
> 审计日期：2026-08-30
>
> 审计对象：当前工作区 11 个仓库
>
> 目的：回答“每个模块已经有什么、真正缺什么、为什么缺、先补什么、做到什么程度才算完成”。

## 1. 结论先行

当前系统不是简单地“还差几个接口”，而是处在以下状态：

1. 机器人本地的前端定位、局部规划、速度仲裁、任务和进桩行为原型已经存在；
2. SLAM 建图主链只有前端，没有后端优化和回环闭环；
3. Planner 是路线跟随和局部避障器，不是完整的全局导航系统；
4. Mission、Docking 的纯行为层较完整，但 Python ROS 运行时存在阻断性接线问题，且二者都需要按计划迁移到 C++；
5. Bridge 已有安全骨架，但 typed authority、完整运动许可和 VBot/S100 唯一速度链尚未闭环；
6. 真实巡检载荷执行器缺失，photo、record、recognize 目前只有合同和客户端；
7. Edge、App、Gateway 存在绕过权威链或协议不匹配的问题；
8. 全栈没有统一 bringup、preflight、不可变 BOM 和目标机联合放行证据。

因此，当前最准确的产品判断是：

> 已有若干可独立运行或测试的模块，但尚未形成一条经过真实接线、故障注入和目标机验证的“建图/定位 → 巡检 → 证据 → 返航 → 进桩 → 充电”闭环。

用户举出的两个例子判断正确，但需要更精确地表述：

- **omni_slam** 不是整个仓库“只有一个节点”，它已有 FAST-LIO 前端、ICP 初始重定位、Manager 和地图版本存储；真正缺的是 SLAM 后端：关键帧、场所识别、回环检测、回环几何验证、位姿图优化、全局轨迹/地图修正和相应地图资产。
- **omni_docking** 的纯 Python 几何与状态机不是废代码，测试价值较高；缺的是可量产的 C++ 运行时、真实相对观测、接触/障碍证据、typed authority、canonical TF 和真机耐久验证。C++ 重构应以 Python 行为为 golden reference，不能直接推倒重写。

## 2. 审计基线

| 仓库 | 当前工作区提交 | 工作区状态 |
| --- | --- | --- |
| omni_robot_interfaces | f0dbd6c40fc2 | clean |
| omni_tf_manager | cc6bd998b694 | clean |
| omni_slam | 2388ed78468f | clean |
| omni_planner | 26d021c6112c | clean |
| omni_robot_bridge | 14f27ca480c6 | clean |
| omni_docking | 67c0d8268d51 | clean |
| omni_mission_manager | 5293de5cfb31 | clean |
| omni-inspection | dbfc9518f1a6 | clean |
| rosdeck | e7794d1e2836 | clean |
| vbot_ros2_msgs | a598337a7c4e | clean |
| omni_navi | d8a1e05bacf2 | clean |

需要注意：当前锁清单中的 **omni_slam、omni_planner、omni_tf_manager、rosdeck** 仍是更早提交。换言之，本次审计看到的源码不全部等于候选发布 BOM 中的源码。这本身就是 omni_navi 的一个集成缺口，详见第 15 节。

## 3. 如何定义“缺失”

### 3.1 五类缺失

| 类别 | 定义 | 典型例子 |
| --- | --- | --- |
| 算法缺失 | 核心算法链不存在 | SLAM 回环/位姿图；Planner 地形可通行性 |
| 运行时缺失 | 纯逻辑或接口存在，但产品节点不可可靠运行 | Mission/Docking Python ROS API 错误 |
| 集成缺失 | 两端都存在，但合同、QoS、frame 或 owner 没接通 | FollowRoute 不校验 map 身份 |
| 产品能力缺失 | 用户闭环需要的 provider 或资产不存在 | Inspection Executor 不存在 |
| 验证缺失 | 实现存在，但没有足够证据允许放行 | 没有目标板 smoke、真机耐久、故障注入 |

### 3.2 优先级

| 优先级 | 判定 |
| --- | --- |
| P0 | 当前就可能导致旁路运动、假成功、错误放行或主链无法运行 |
| P1 | 真实短路线巡检试点前必须补齐 |
| P2 | 大场景、长期运行或量产候选前必须补齐 |
| P3 | 多机、高级智能、体验或规模化增强 |

### 3.3 “完成”的最低标准

一个模块不能因为“有文件”“有 Topic”“有单元测试”就判定完成。至少同时满足：

1. 合同存在且由唯一 owner 提供；
2. 运行时正常、取消/超时/重启语义明确；
3. 与上下游的 frame、时间戳、QoS、版本和错误码一致；
4. 关键失败路径 fail-closed；
5. 有节点级或跨进程测试；
6. 在目标平台上有可追踪的构建与运行证据；
7. 若涉及真实世界成功，还必须有传感器或业务证据，而不是只看软件状态。

## 4. 全局缺口地图

| 模块 | 当前真实能力 | 最主要缺失 | 当前判断 |
| --- | --- | --- | --- |
| omni_robot_interfaces | 5 msg、10 srv、5 action 的产品合同 | Authority V2、统一 SLAM/readiness、typed 模式、资产/能力合同 | 合同基础可用，V2 未冻结 |
| omni_tf_manager | TF authority、外参、alias、body odom、ready | ready 语义不足、在线后端修正合同、完整真机标定 | 核心已成形，放行门不足 |
| omni_slam | FAST-LIO 前端、ICP 初始重定位、Manager、PCD 版本库 | SLAM 后端、回环、图优化、地图 bundle、持续恢复 | 明确缺后端 |
| omni_planner | 3D 局部占据图、A*/B-spline、FollowRoute、控制器 | 真正全局规划、地图绑定、地形/动态障碍、完整恢复 | 强局部规划器，不是完整导航栈 |
| omni_robot_bridge | SDK owner、仲裁、E-stop、BMS、RobotState | typed authority、完整运动 gate、统一 stamped 输入、VBot 真实闭环 | 安全骨架存在，权威链未闭合 |
| omni_docking | Python 状态机、地图位姿伺服、Dock/Undock、充电推断 | C++、相对观测、接触/障碍、标定、耐久证据 | 行为原型，不可宣称真机自动回充 |
| omni_mission_manager | 任务状态机、路线、检查点、SQLite、RTD 编排 | C++、ROS 接线修复、载荷 provider、恢复/存储工程化 | 纯逻辑较强，运行时阻断 |
| omni-inspection | Cloud、Web、Edge、视频、数据库、MQTT | Inspection Executor、Edge 权威化、可靠消息、真实地图/位姿 | 平台丰富，机器人闭环缺失 |
| rosdeck | App、teleop、任务 UI、Foxglove/rosbridge、WSS gateway | binary proxy、pin enforcement、typed 控制、真实 E2E | UI 可用，安全传输主链有断点 |
| vbot_ros2_msgs | 15 个供应商纯 IDL 包 | runtime/ABI/能力发现和 Omni adapter 验证 | 不是功能模块，不能按 IDL 数量算完成度 |
| omni_navi | manifest、构建脚本、架构和版本审计 | bringup、preflight、BOM 更新、全栈 Matrix/目标板放行 | 集成仓职责明确，运行组合缺失 |

## 5. omni_robot_interfaces

### 5.1 已有边界

该仓库只负责跨仓产品合同，不运行节点。目前已经覆盖：

- RobotState、MissionStatus、MissionEvent、CheckpointResult、DockStatus；
- Mission dispatch/control/results、Route list、Dock config、Charge verify；
- CapturePhoto、StartRecord、Recognize；
- FollowRoute、ExecuteInspection、ReturnToDock、Dock、Undock；
- ControlAuthority V1。

这部分不是“缺少接口仓”，而是合同从 V1 走向可安全运行的 V2 尚未完成。

### 5.2 缺失清单

| ID | 缺失 | 证据/现状 | 影响 | 优先级 |
| --- | --- | --- | --- | --- |
| IF-01 | SLAM 状态合同没有归一 | SlamStatus 在 omni_tf_manager，SLAM action/service 又在 omni_slam_interfaces | owner、版本和依赖分裂 | P0 |
| IF-02 | ControlAuthority 缺 lease token/epoch | V1 只有 owner/client/lease 秒数 | 重启、旧 renew、ABA 式 owner 复用难以拒绝 | P0 |
| IF-03 | release/preemption 结果不完整 | 没有明确 release ack、被谁抢占、何时生效 | Mission/Docking 无法证明零速交接完成 | P0 |
| IF-04 | RobotState.motion_authorized 语义太弱 | 合同注释定义为“无 E-stop 且持 lease” | 可能在定位丢失、TF 未 ready、adapter fault 时仍为 true | P0 |
| IF-05 | 缺结构化 readiness | 当前主要靠 Bool ready 和聚合字符串 | 无法表达哪个 gate 失败、数据年龄和 epoch | P0 |
| IF-06 | 姿态/步态/运行模式仍无 Omni typed 合同 | Bridge 继续使用 String 或厂商服务 | App/Edge 与厂商 ABI 耦合 | P1 |
| IF-07 | StartRecord 用阻塞 Service | 最长可请求 600 秒 | cancel、feedback、超时、provider 重启语义不足 | P1 |
| IF-08 | 缺机器人能力发现 | 没有 adapter capability/schema/version 消息或服务 | 无法区分 VBot/ZsiBot 是否支持 BMS、姿态、横移、视频等 | P1 |
| IF-09 | 资产身份没有形成统一 bundle 合同 | Map/Route/Dock/Calibration 分散为字段/文件 | 同名不同版本或标定错配无法统一拒绝 | P1 |
| IF-10 | 证据只返回本地路径 | CheckpointResult 有 artifact_path，但缺 hash、size、mime、capture time、upload state | 云端无法可靠去重和验真 | P1 |

### 5.3 建议的最小 V2

ControlAuthority V2 至少增加：

- request_id、client_epoch、lease_token；
- accepted_at、expires_at；
- previous owner、preempted 标志和原因；
- release_completed 与 active owner 快照；
- 结构化 reason enum，文本只作诊断；
- 明确服务进程重启后所有旧 token 失效。

RobotState/readiness 至少增加或明确：

- tf_ready、slam_initialized、slam_state_fresh；
- adapter_ready、command_source_fresh；
- motion gate bitmask 和主要拒绝原因；
- state_epoch、authority_epoch；
- header.stamp 必须由发布者写入，不能保持零值。

### 5.4 验收

- 生成代码、常量和 ABI gate 覆盖 V1/V2；
- Bridge、Mission、Docking、Rosdeck 使用同一 contract fixture；
- Bridge 重启后旧 renew/release 全部拒绝；
- APP 抢占 MISSION/DOCKING 时，结果能证明旧 owner 已失效且输出已归零；
- 每个 motion gate 都能被单独注入失败并在 RobotState 中看到结构化原因。

## 6. omni_tf_manager

### 6.1 已有边界

当前模块已经实现：

- canonical map/odom/base/sensor frame；
- authority 与 shadow 两种模式；
- profile 驱动的静态 6DoF 外参；
- sensor header identity alias；
- sensor odom 到 body odom 的变换；
- mapping identity map→odom；
- localization 时把 ICP map→LiDAR 归一成 map→odom；
- ready Bool 和 diagnostics。

因此缺失不是“没有 TF 管理器”，而是 ready、真机标定和未来 SLAM 后端修正还没形成放行级合同。

### 6.2 缺失清单

| ID | 缺失 | 证据/现状 | 影响 | 优先级 |
| --- | --- | --- | --- | --- |
| TF-01 | ready 未检查 SlamStatus.initialized | computeReady 只看 mode、sensor odom 和 map_initialized | SLAM 尚未真正初始化也可能 ready | P0 |
| TF-02 | ready 未按 state 拒绝 DEGRADED/LOST/ERROR | slam_state 仅进入 diagnostics，不参与 computeReady | 定位状态坏但 TF 数据仍新鲜时可能假 ready | P0 |
| TF-03 | shadow ready 语义容易被误用 | shadow 也可发布“candidate ready” Bool | 下游只看 Bool 时无法确认谁是 TF authority | P0 |
| TF-04 | VBot profile 文档与配置漂移 | YAML 已是 authority，README 仍写 intentionally shadow | 部署人员可能错误判断 publisher ownership | P0 |
| TF-05 | 不支持连续后端修正合同 | 当前主要接收 ICP，且默认只接受一次 map 初始化 | 在线回环/图优化无法安全更新 map→odom | P1 |
| TF-06 | 缺修正平滑/跳变策略 | 只有 reinitialization jump limit | 后端修正可能造成控制坐标跳变 | P1 |
| TF-07 | Dog/VBot 全传感器审核不完整 | LiDAR/IMU 部分已审，Depth/RGB/CameraInfo 和全机型现场记录不完整 | 感知、巡检证据与规划可能错位 | P1 |
| TF-08 | identity alias 没有自动证明 | 它只改 header，不变换 payload | 如果传感器实际轴/原点不同，会产生静默坐标错误 | P1 |
| TF-09 | 缺标定工具和标定质量报告 | 主要依赖人工 YAML/来源说明 | 量产换机、换传感器难复现 | P2 |
| TF-10 | 缺 lifecycle 和明确 readiness 消息 | 当前 Bool + diagnostics | bringup 很难做结构化依赖 | P1 |

### 6.3 为 SLAM 后端预留的修正合同

在线后端不应自己发布 TF。建议由后端输出一个 correction 消息，TF Manager 仍是唯一 map→odom owner。消息至少包含：

- source：initial_icp、loop_backend、manual_relocalization；
- map_id、map_version、map_checksum；
- backend_epoch、sequence；
- T_map_odom；
- 6x6 covariance；
- valid_from 和观测时间；
- correction magnitude；
- 是否允许平滑、建议平滑窗口；
- 后端健康和拒绝原因。

TF Manager 需要实现：

1. sequence/epoch 去旧；
2. 地图身份一致性检查；
3. 单次跳变和累计修正上限；
4. stationary-only、平滑或立即应用策略；
5. 修正期间暂时撤销自动运动许可；
6. 发布 correction accepted/rejected 诊断；
7. 回滚或后端失联时保持最后有效 TF，但 readiness 按策略降级。

### 6.4 验收

- initialized=false、STATE_LOST、STATE_ERROR、状态超时均使 ready=false；
- shadow 模式不会被产品启动链当成 authority ready；
- 对每个 robot profile 做 topic/header/extrinsic/CameraInfo 现场审计；
- 后端连续小修正平滑通过，大跳变在运动时拒绝；
- TF child publisher audit 证明每条受管 TF 只有一个 owner。

## 7. omni_slam

### 7.1 当前到底是什么

当前 SLAM 由三部分组成：

1. **FAST-LIO 前端**：LiDAR+IMU 紧耦合迭代卡尔曼滤波，输出 odometry，并使用 ikd-tree 做局部/增量地图匹配；
2. **ICP 初始重定位**：当前帧对先验 PCD 做配准，得到启动时 map 对齐；
3. **SLAM Manager/Map Store**：进程监督、Start/Stop/Save/Localize、状态、地图版本和 checksum。

FAST-LIO 中出现“ICP”字样不等于有 SLAM 后端。它表示前端 scan-to-map 更新。独立 icp_relocalization 也只是初始对齐，不是回环检测。

### 7.2 明确缺失的后端

| ID | 缺失 | 当前证据 | 直接后果 | 优先级 |
| --- | --- | --- | --- | --- |
| SLAM-01 | 关键帧管理 | 无关键帧选择、落盘、生命周期模块 | 无法建立稳定后端节点 | P1 |
| SLAM-02 | 场所识别/回环候选 | 无 Scan Context、BoW 或同类描述子链路 | 机器人回到旧地点也不会发现回环 | P1 |
| SLAM-03 | 回环几何验证 | ICP 只用于初始重定位 | 无法可靠过滤假回环 | P1 |
| SLAM-04 | 位姿图/因子图 | 依赖中无 GTSAM/Ceres 等图优化器 | 累积漂移不会全局分摊 | P1 |
| SLAM-05 | 全局轨迹修正 | 只有前端实时轨迹 | 长闭环路线首尾会错位 | P1 |
| SLAM-06 | 地图变形/重建 | map 主要是单个 PCD | 优化后的轨迹不能生成一致地图 | P1 |
| SLAM-07 | 后端到 TF 的修正合同 | 当前 TF Manager 主要一次性接受 ICP | 在线回环结果无法进入权威 TF | P1 |
| SLAM-08 | 后端资产 | MapStore 只有 map.pcd + manifest | 无 descriptors、keyframes、graph、trajectory、quality report | P1 |

### 7.3 其他算法/产品缺失

| ID | 缺失 | 影响 | 优先级 |
| --- | --- | --- | --- |
| SLAM-09 | 持续重定位和 LOST 自动恢复 | 初始 ICP 成功后，后续丢失没有完整恢复策略 | P1 |
| SLAM-10 | 多子图/内存生命周期 | 大地图长期建图时 ikd-tree 和 PCD 规模难控 | P2 |
| SLAM-11 | 多会话地图更新/合并 | 无法安全把新区域或环境变化并入旧图 | P2 |
| SLAM-12 | 动态物体过滤 | 人车密集场景会污染地图与匹配 | P1/P2 |
| SLAM-13 | 退化检测和观测性指标 | 现有 freshness/fitness 不等于几何退化评估 | P1 |
| SLAM-14 | 轮速/GNSS/视觉等可选因子 | 长走廊、开阔区或振动场景缺额外约束 | P2，按平台 |
| SLAM-15 | 地图质量报告 | 无覆盖率、密度、漂移、闭环残差、动态比例 | P1 |
| SLAM-16 | 可复现精度回归 | 缺固定数据集上的 APE/RPE、重定位成功率门槛 | P1 |

### 7.4 推荐的后端结构

建议在现有仓库内新增 **omni_slam_backend** package，而不是再建一个仓库。

~~~text
FAST-LIO frontend
  ├─ high-rate odom
  ├─ registered cloud
  └─ keyframe candidate
          |
          v
Keyframe Manager
  ├─ keyframe pose/cloud
  ├─ odom edge
  └─ descriptor
          |
          +------> Loop Detector
          |          ├─ candidate retrieval
          |          └─ temporal/spatial exclusion
          |
          +------> Loop Verifier
                     ├─ coarse alignment
                     ├─ ICP/GICP/NDT refinement
                     └─ overlap/residual/covariance gate
                            |
                            v
                     Pose Graph Optimizer
                            |
                +-----------+-----------+
                v                       v
        optimized trajectory      optimized map artifact
                |
                v
       correction to TF Manager
~~~

### 7.5 推荐分两阶段实现

#### 阶段 A：离线后端，先解决地图质量

- 建图时保存关键帧、前端位姿、时间戳和描述子；
- 建图结束后执行回环候选、几何验证和图优化；
- 用优化轨迹重新拼接 PCD；
- 生成新的不可变 MapBundle 版本；
- 报告回环数量、最大修正、残差、地图大小和失败原因；
- 定位运行时仍只使用已优化的稳定地图。

这样不会立即引入在线 TF 跳变，工程风险最低。

#### 阶段 B：在线后端，解决长时间定位漂移

- 后端持续接收关键帧并增量优化；
- 通过受版本控制的 correction 合同交给 TF Manager；
- correction 应用期间 Planner/Bridge 按策略暂停或限速；
- 必须验证控制连续性、跳变拒绝和后端重启 epoch。

### 7.6 MapBundle 应补齐

~~~text
MapBundle/<map_id>/<version>/
  manifest.json
  map.pcd
  keyframes/
  trajectory_frontend.csv
  trajectory_optimized.csv
  descriptors.bin
  pose_graph.bin
  calibration.yaml
  quality_report.json
  preview.png
~~~

manifest 至少绑定：

- schema/version；
- map frame；
- sensor profile/calibration hash；
- frontend/backend 算法版本；
- 输入数据集/会话身份；
- 所有文件的 size/hash；
- 地图边界、点数和质量指标；
- 是否允许用于 mapping、localization 或仅调试。

### 7.7 验收

离线后端最低验收：

- 固定闭环数据集上能检测真实回环；
- 测试集假回环为零或低于冻结阈值；
- 优化后 APE/RPE 和首尾闭合误差显著下降；
- 生成 MapBundle 可由 Manager 校验并定位；
- 后端失败不会覆盖 current map。

在线后端最低验收：

- 运动中大修正 fail-closed；
- 小修正不会让速度控制产生不连续；
- 后端重启、序列回退、地图错配全部拒绝；
- 24 小时运行无图无限增长、无 correction 风暴。

### 7.8 优先级说明

短距离、不开环的小型试点可以暂时使用前端+优化后的离线地图，但不能把它当成 SLAM 已完成。以下任一条件出现时，后端应升级为 P1：

- 路线存在明显闭环；
- 单程长、重复巡检时间长；
- 首尾或跨楼层/跨区域漂移超标；
- 需要多会话更新地图；
- Dock、检查点或证据位置要求高重复精度。

## 8. omni_planner

### 8.1 已有边界

当前 Planner 已有：

- 滑动 3D 概率占据栅格和膨胀；
- 局部搜索、B-spline 优化和轨迹终验；
- FollowRoute Action；
- 路线进度、心跳、cancel、局部重规划；
- 闭环 controller 和保守的局部 recovery sweep；
- 简单 waypoint/RViz goal 到 Path 的 GlobalPathPublisher。

这里的 GlobalPathPublisher 只是生成/发布参考线，不读取持久地图做全局搜索。因此它不能被算作完整 global planner。

### 8.2 缺失清单

| ID | 缺失 | 证据/现状 | 影响 | 优先级 |
| --- | --- | --- | --- | --- |
| PLAN-01 | 真正的全局路径规划 | global_path_publisher 只连当前位姿与配置点/目标 | 长距离封路时只能围绕局部参考线处理 | P1/P2 |
| PLAN-02 | 持久地图/拓扑/语义路由 | 主要消费局部点云和给定 Path | 不能选择替代走廊、楼层或任务通道 | P2 |
| PLAN-03 | map_id/map_version 实际校验 | FollowRoute Goal 有字段，但 server 未使用 | 路线可能在错误地图上执行 | P0 |
| PLAN-04 | RobotState/SLAM 状态 gate | 主要看 odom 与可选 TF ready | 定位 degraded/lost 和地图错配不能完整拒绝 | P0 |
| PLAN-05 | 产品默认 fail-open | run.launch.py 的 require_tf_ready 默认 false | 未覆盖参数时可能绕过 ready | P0 |
| PLAN-06 | stamped canonical navigation velocity | 当前默认 /scan_planner/cmd_vel Twist | 无源时间戳，Bridge 只能按到达时间判断 | P0/P1 |
| PLAN-07 | 动态障碍跟踪与预测 | 局部图主要是占据快照 | 对移动人车只能被动反应 | P1 |
| PLAN-08 | 地形可通行性 | 无完整坡度、台阶、悬崖/负障碍、地面类别 cost layer | 机器狗/轮式平台都可能遇到几何盲区 | P1 |
| PLAN-09 | 语义安全区 | 无本地 keepout、slow zone、geofence enforcement | 云端配置不能成为本地运动约束 | P1 |
| PLAN-10 | 定位不确定度限速 | 未消费 covariance/degradation 做速度包络 | 定位差时仍可能按正常速度运行 | P1 |
| PLAN-11 | 全局级恢复编排 | 有局部 sweep，但无全局重路由/行为树/有界恢复政策 | 持续堵塞时缺可解释终态 | P1 |
| PLAN-12 | 平台运动学能力合同 | Go2 gait publisher 是模拟展示，不是步态/足端规划 | 不能按真实横移、转弯、坡度能力规划 | P2 |
| PLAN-13 | 资源和实时预算 | 有 deadline 帮助类，但无整机 CPU/jitter 门槛 | 目标板高负载下无法放行 | P1 |
| PLAN-14 | 真机/HIL 回归 | 单元和离线工具较多，缺系统性路障、定位丢失、动态人群回归 | 算法存在不等于产品可用 | P1 |

### 8.3 建议补齐结构

不建议复制 Nav2 业务栈。保持 FollowRoute 为唯一执行合同，在其下分层：

1. **Route Resolver**：验证 route/map/calibration identity；
2. **Global Route Planner**：按持久栅格或拓扑图生成走廊级路径；
3. **Local Planner**：保留现有 SCAN Planner；
4. **Trajectory Validator**：继续作为最终几何终验；
5. **Controller**：输出 stamped navigation candidate；
6. **Recovery Coordinator**：stop → wait → local retry → global reroute → bounded failure；
7. **Safety Cost Layers**：negative obstacle、terrain、keepout、slow zone；
8. **Readiness Gate**：TF、SLAM、RobotState、map/route identity、source freshness。

### 8.4 验收

- 错 map_id/version 的 FollowRoute 在运动前返回 REASON_MAP_MISMATCH；
- require_tf_ready 产品配置无覆盖时也必须为 true；
- LOC_DEGRADED 限速，LOC_LOST 清轨迹并输出零；
- 持续封路能产生替代全局路线，或在有界次数后明确失败；
- cliff/negative obstacle/keepout 测试均不会生成穿越轨迹；
- 所有候选速度带 source stamp/sequence，Bridge 可拒绝旧命令；
- x86、Orin、S100 上记录规划周期、最坏延迟和丢 deadline 指标。

## 9. omni_robot_bridge

### 9.1 已有边界

Bridge 当前已经是最接近产品安全边界的模块：

- 单一厂商 SDK owner；
- ZsiBot 和 VBot adapter；
- teleop/navigation/docking 三源速度仲裁；
- E-stop latch、watchdog、直接 adapter stop；
- BMS/adapter observability；
- RobotState 聚合；
- 部署、运行锁、A/B 发布基础。

问题不在于“没有 Bridge”，而在于 typed authority 和最终运动许可仍没有闭环。

### 9.2 缺失清单

| ID | 缺失 | 证据/现状 | 影响 | 优先级 |
| --- | --- | --- | --- | --- |
| BR-01 | /omni/control/authority provider | 只有 /rosdeck/control_command/status String | Mission typed client无法工作 | P0 |
| BR-02 | 单一 V2 lease state machine | typed facade 尚无，token/epoch 也缺 | 新旧入口可能产生语义分叉 | P0 |
| BR-03 | 完整 motion gate | motion_authorized 只看 E-stop+lease | 定位/TF/adapter/source 不满足仍可显示 true | P0 |
| BR-04 | navigation/docking 的 stamped 输入 | 两者是 Twist，teleop 才是 TwistStamped | 无源时间和序列，重放防护较弱 | P0/P1 |
| BR-05 | TF ready 进入最终仲裁 | TODO 明确未接 | Planner 自己的 gate 失效时 Bridge 无最后保护 | P0 |
| BR-06 | SLAM initialized/state/freshness 进入最终仲裁 | RobotState 映射状态，但 arbiter 不完整消费 | 定位丢失停车闭环不足 | P0 |
| BR-07 | final ROS seam 仍公开 | /omni/cmd_vel/final 是可见 Topic | 未授权 publisher 可能注入最终速度 | P1 |
| BR-08 | typed 姿态/步态/建图控制 | 仍使用 String/厂商服务 | 上层耦合 vendor 文本和 ABI | P1 |
| BR-09 | adapter 能力发现/配置 schema | 主要靠 YAML 开关 | 不同机型 unsupported 能力难 fail-fast | P1 |
| BR-10 | VBot 实际 BMS/运动链权威证据 | VBot adapter 状态源有限，外部 Edge 仍可直发 /vel_cmd | 不能证明 Bridge 是唯一真实速度出口 | P0 |
| BR-11 | lifecycle/readiness/systemd watchdog | 有部署基础但无统一结构化 readiness | omni_robot_bringup 难做可靠编排 | P1 |
| BR-12 | HIL 和实时预算 | 单元测试强，厂商断连/进程杀死/延迟证据不足 | 量产安全无法仅靠 pure tests 证明 | P1/P2 |
| BR-13 | 结构化诊断 reason | 多处 String summary | 云端/运维难稳定聚合 | P1 |

### 9.3 最终运动许可建议

自动运动的最终允许条件应是所有条件的逻辑与：

~~~text
valid_authority
AND authority_epoch_current
AND not_estop
AND safety_supervisor_armed
AND adapter_ready
AND tf_authority_ready
AND slam_initialized
AND localization_state_allowed
AND localization_fresh
AND map_identity_matches
AND selected_source_fresh
AND selected_source_sequence_current
AND posture_allows_motion
AND local_geofence_allows_motion
~~~

Teleop 可以按产品策略放宽 localization，但不能放宽 E-stop、authority、adapter、source freshness 和硬件安全。

### 9.4 验收

- typed 和 legacy façade 共用一个内部 lease 对象；
- Bridge 重启使旧 lease 全部失效；
- APP 抢占时旧导航/进桩缓存立即清除；
- TF/定位/adapter/source 任一失效，最终输出在冻结 deadline 内变零；
- VBot/S100 ROS 图和厂商进程审计证明只有 Bridge 能到真实底盘；
- /omni/cmd_vel/final 移入进程内调用，或通过 SROS2+启动审计限制 publisher；
- SDK disconnect、stop failure、重复 publisher、shutdown ordering 有 HIL 证据。

## 10. omni_docking

### 10.1 当前已有且应保留的部分

Python 版本已有：

- Dock/Undock Action 行为；
- 单活动操作、幂等 request_id；
- 地图版本到 dock 配置查找；
- approach/undock 纯几何控制器；
- lease acquire/heartbeat/release；
- E-stop、状态/pose stale、lease loss、timeout 终止；
- 充电状态/电流推断；
- 终态前零速和 release；
- 大量 pure Python 测试。

这些逻辑应作为 C++ 重构的行为规范和 golden vector。

### 10.2 为什么必须 C++ 重构

| 原因 | 当前表现 | C++ 目标 |
| --- | --- | --- |
| ROS API 正确性 | is_cancel_requested 按函数调用；当前 rclpy 合同为属性 | 用 rclcpp Action 标准 cancel callback 和线程模型 |
| 执行确定性 | asyncio execute callback + timer + Python GC | 固定周期、无阻塞 servo callback |
| 安全审计 | 字符串 lease、动态类型、异常路径分散 | typed authority、RAII zero/release guard |
| 目标板资源 | 20 Hz 控制虽不高，但与 Python 运行时/依赖绑定 | 小型静态 C++ runtime |
| 与 Bridge/TF 集成 | Twist、legacy frame/pose、String lease | TwistStamped、tf2、V2 authority/readiness |
| 未来感知 | 真实相对观测和多传感器需要线程安全缓存 | 明确 observation provider 接口 |
| 可验证性 | 主要是 pure Python point-robot | property/fuzz、launch、Matrix、HIL 共用 core |

### 10.3 除 C++ 外仍缺的能力

| ID | 缺失 | 证据/现状 | 影响 | 优先级 |
| --- | --- | --- | --- | --- |
| DOCK-01 | typed authority | 当前使用 /rosdeck/control_* String | 与 Mission/Bridge V2 断链 | P0 |
| DOCK-02 | canonical TF/ready | 默认 lio_map + /state_estimation_global，frame 错配只 warning | 错坐标也可能继续伺服 | P0 |
| DOCK-03 | 真实相对观测 | 只用全局机器人 pose 和固定 dock pose | 全局定位误差会直接变成进桩误差 | P1 |
| DOCK-04 | 观测质量 | 无 covariance、confidence、freshness、source ID | 无法区分可用/假目标 | P1 |
| DOCK-05 | 接触证据 | 无触点、限位、bumper、桩通信等 provider | 到 pose 不等于物理接触 | P1 |
| DOCK-06 | 最后阶段障碍/人员 gate | 无局部 obstacle/person/negative obstacle 输入 | 进桩/出桩可能碰撞 | P1 |
| DOCK-07 | 充电证据来源确认 | 主要依赖 BatteryState 推断 | 电流符号或 BMS source 错会假成功/假失败 | P1 |
| DOCK-08 | 标定和 guided capture | dock pose 主要靠 JSON 手工配置 | 现场部署不可重复 | P1 |
| DOCK-09 | footprint/stopping distance 版本化 | 控制参数未绑定机型/标定 hash | 换底盘后安全包络失效 | P1 |
| DOCK-10 | 有界 recovery/backout | 当前明确不自动 retry | 失败后缺安全退回与调用方策略 | P1 |
| DOCK-11 | 追踪记录 | 缺 observation/command/contact/BMS trace | 现场失败难复盘 | P1 |
| DOCK-12 | 50–100 次耐久基线 | 现有是模拟测试 | 无法声明自动回充成功率 | P1 |
| DOCK-13 | 多 dock/预约 | V1 每地图最多一桩 | 多机器人/多充电位不支持 | P3 |
| DOCK-14 | license 根合同 | 仓库 TODO 已标记冲突 | 外发/产品发布风险 | P0 |

### 10.4 推荐 C++ 组件

~~~text
omni_docking_core
  DockingStateMachine
  DockGeometry
  ApproachController
  UndockController
  RecoveryPolicy
  ChargeVerifier
  SafetyEnvelope

omni_docking_ros
  DockingNode
  Dock/Undock Action servers
  DockRegistry service
  AuthorityClient
  TfPoseProvider
  RelativeObservationProvider
  ContactProvider
  ObstacleProvider
  BatteryProvider
  TwistStampedOutput
  TraceRecorder
~~~

核心库不得依赖 ROS 时钟和全局单例。所有输入通过一个显式 Snapshot 进入，所有输出通过 Command/Event 返回，时间使用注入的 monotonic time。

### 10.5 推荐状态机

~~~text
IDLE
  -> PRECHECK
  -> ACQUIRE_AUTHORITY
  -> WAIT_OBSERVATION
  -> ALIGN
  -> APPROACH
  -> CONTACT
  -> VERIFY_CHARGE
  -> SUCCESS

任意运动态:
  cancel / estop / lease lost / stale / obstacle
  -> ZERO
  -> optional bounded BACKOUT
  -> RELEASE
  -> FAILED or CANCELED

UNDOCK:
  PRECHECK -> ACQUIRE -> VERIFY_CLEAR -> BACKOUT
  -> CLEARANCE_REACHED -> ZERO -> RELEASE -> SUCCESS
~~~

自动 recovery 必须有界。推荐只允许：

- 低速停止；
- 若接触失败且后方安全，后退固定小距离；
- 重新获取观测；
- 最多 N 次，由 goal policy 或 Mission 明确授权；
- 任何 obstacle、E-stop、lease loss、定位 lost 直接终止，不自动重试。

### 10.6 迁移顺序

1. 冻结 Python 测试向量和终态 reason；
2. 建 C++ pure core，逐条 golden parity；
3. 接 V2 Authority、RobotState、TF 和 TwistStamped；
4. 用 fake providers 完成 cancel/E-stop/stale/lease-loss launch tests；
5. 接 Matrix 相对观测；
6. 接真实相机/AprilTag/IR/桩通信中的一个主 provider；
7. 加 contact/obstacle/BMS 证据；
8. Python 与 C++ shadow compare；
9. C++ 成为默认，Python 保留一个版本作为回滚；
10. 达到耐久门槛后再删除 Python runtime。

### 10.7 验收

- C++ core 与 Python golden 终态/速度包络一致；
- frame 错配直接拒绝，不再 warning 后继续；
- 没有 fresh relative observation 时不会进入最后 approach；
- 接触、充电和 pose 三类证据均满足才成功；
- cancel/E-stop/lease loss 在固定 deadline 内观测到零速；
- 50–100 次 dock/undock 给出成功率、耗时、最终误差、接触次数、充电确认延迟；
- 所有失败都有 trace_id，可关联 observation、command、BMS 和 reason。

## 11. omni_mission_manager

### 11.1 当前已有且应保留的部分

当前 Python pure core 已覆盖：

- Mission 生命周期和幂等；
- route/sidecar/checkpoint 解析；
- FollowRoute 分段；
- pause/resume/cancel 的行为基础；
- SQLite mission/event/checkpoint persistence；
- restart 后 active → INTERRUPTED；
- photo/record/recognize checkpoint runner；
- ReturnToDock 两段编排和低电触发；
- 丰富的 pure tests。

### 11.2 运行时阻断

| ID | 缺失/缺陷 | 证据 | 影响 | 优先级 |
| --- | --- | --- | --- | --- |
| MIS-01 | Future.wait_for_future 不存在 | authority 和 dock config 调用使用该 API | typed 服务路径运行即失败 | P0 |
| MIS-02 | ServerGoalHandle.goal 使用错误 | execute/return callback 读取 goal_handle.goal | Action server 主路径失败 | P0 |
| MIS-03 | Authority provider 缺失 | 客户端已建，Bridge 尚未提供 | Mission 无法取得 MISSION lease | P0 |
| MIS-04 | TF ready 未进入 dispatch gate | 主要依赖 RobotState 和 legacy pose | 可能在 TF 未稳定时发路线 | P0 |
| MIS-05 | legacy frame/pose | 默认 lio_map、/state_estimation_global | canonical 迁移未完成 | P0/P1 |
| MIS-06 | Inspection provider 缺失 | client/IDL 有，产品 provider 无 | 检查点会失败 | P0/P1 |
| MIS-07 | 长录像仍是阻塞 service | 最长 600 秒 | cancel/pause/provider restart 语义差 | P1 |
| MIS-08 | 默认 C++ runtime 缺失 | 近期计划已要求 C++ | 目标板可靠性与统一实现不足 | P0/P1 |
| MIS-09 | 任务完成自动返航未闭环 | ReturnToDock 支持 trigger，但完成后自动调用链未形成产品证据 | 任务结束不会可靠回桩 | P1 |
| MIS-10 | 出桩链未编排 | Undock 合同存在，但任务开始前没有完整自动链 | 在桩上开始任务会卡住或依赖人工 | P1 |
| MIS-11 | crash 后只 INTERRUPTED，无恢复工作流 | 明确 never auto-resumed | 安全但运维无法选择从安全点恢复 | P1 |
| MIS-12 | SQLite 工程化不足 | 无正式 migration/backup/disk-full/retention policy | 长期运行或升级可能阻断任务 | P1 |
| MIS-13 | 载荷资源锁 | 无 camera/record/model 资源协调 | 多 checkpoint/视频流可能冲突 | P1 |
| MIS-14 | route 仍是文本+sidecar | 缺完整 RouteBundle/迁移/签名 | 路线资产容易漂移 | P1 |
| MIS-15 | 生命周期/监控/指标 | 无统一 lifecycle/readiness/watchdog | 全栈 bringup 难放行 | P1 |
| MIS-16 | 故障注入不足 | pure tests 强，跨进程 durable transition 证据不足 | 断电/磁盘满/结果丢失边界未知 | P1 |
| MIS-17 | license 根合同 | 仓库 TODO 已标记冲突 | 外发风险 | P0 |

### 11.3 推荐 C++ 结构

~~~text
omni_mission_core
  MissionStateMachine
  SegmentCoordinator
  CheckpointRunner
  ReturnToDockCoordinator
  Route/Checkpoint validators
  RecoveryPolicy

omni_mission_store
  SQLiteStore
  TransactionBoundary
  SchemaMigration
  EventOutbox
  Retention/Quota

omni_mission_ros
  ExecuteInspection server
  Dispatch/Control/Results services
  FollowRoute client
  Dock/Undock/Return clients
  Inspection Executor clients
  Authority/Readiness clients
  Status/Event publishers
~~~

所有外部调用都必须异步，状态机不能在 ROS callback 内阻塞等待 Future。每一个“先持久化还是先发外部命令”的顺序都要冻结成事务/幂等规则。

### 11.4 任务完整链应变成

~~~text
Dispatch
 -> validate Bundle identity
 -> validate RobotState/TF/SLAM
 -> if docked: Undock
 -> acquire MISSION
 -> FollowRoute segments
 -> checkpoint actions through Inspection Executor
 -> persist evidence + outbox
 -> release MISSION
 -> ReturnToDock when policy requires
 -> Dock acquires DOCKING
 -> charging confirmed
 -> terminal report
~~~

### 11.5 验收

- C++ 对 Python golden 状态/事件/reason parity；
- authority、FollowRoute、payload、Dock 全部异步且可 cancel；
- 进程在每个 durable transition 被 kill，重启后不重发已完成动作；
- DB schema 可升级/回滚，磁盘满时拒绝新任务且不破坏旧记录；
- 任务开始可自动出桩，任务完成/低电按策略返航；
- 载荷 evidence 有 hash、outbox 和重试；
- Python 在一个 RC 周期 shadow 后才退出默认运行时。

## 12. omni-inspection

### 12.1 当前已有边界

该仓库不是一个单模块，而是：

- Go backend；
- PostgreSQL/Redis/MQTT/WebSocket；
- Web Console；
- C++ Edge Agent；
- 视频采集、转码、MediaMTX/WHEP 等链路；
- 地图、任务、告警、地理围栏、用户/RBAC 等平台能力。

平台面功能较丰富，但机器人本地“巡检执行”和权威控制没有接入完整 Omni 链。

### 12.2 缺失清单

| ID | 缺失 | 证据/现状 | 影响 | 优先级 |
| --- | --- | --- | --- | --- |
| INS-01 | omni_inspection_executor 不存在 | Mission 有 photo/record/recognize client，仓内无 Omni provider | 真实巡检证据链断开 | P0 |
| INS-02 | Edge 直接发 /vel_cmd | agent.s100.yaml 配置 /vel_cmd | 绕过 Bridge authority/arbiter/safety | P0 |
| INS-03 | Edge 直接调用厂商模式服务 | SetRunMode/LowlevelAction | 产生第二个 robot adapter owner | P0 |
| INS-04 | Edge 重复 patrol/navigation 状态机 | 自有 patrol thread + Nav2 adapter | 与 Mission/Planner 形成双业务入口 | P0 |
| INS-05 | production 可落入 simulation | 默认/fallback SimulationRobotAdapter 和 SimulationNavigationAdapter | 机器不动也可上报任务成功 | P0 |
| INS-06 | map activate 只缓存 identity | Nav2 activateMap 注释明确由外部栈加载 | 云端显示 active 不等于机器人已定位 | P0 |
| INS-07 | telemetry pose 固定 0 | telemetryJson 写死 x/y/yaw=0 | 云端轨迹、围栏和告警不可信 | P0/P1 |
| INS-08 | MQTT publish 是 QoS 0 | PUBLISH header 0x30，无 packet id/PUBACK | ACK、事件、证据元数据可能静默丢失 | P1 |
| INS-09 | Clean Start + 无 durable outbox | 手写客户端不保留 session/inflight | 断网后命令结果不可恢复 | P1 |
| INS-10 | command dedup/重放保护不完整 | message_id 可 fallback 本地生成，未形成持久执行账本 | 云端重发可能重复动作 | P1 |
| INS-11 | 设备 mTLS 未形成 Edge 主链 | 客户端是普通 TCP 用户名密码 | 设备身份和链路保护不足 | P1 |
| INS-12 | geofence 主要在云端告警 | Backend 检查位置，未进入本地最终 motion gate | 断网时围栏不生效 | P1 |
| INS-13 | 地图资产同步不完整 | 云端有上传/hash，机器人 activate 不下载/校验/import | map identity 不是事实 | P1 |
| INS-14 | 视频路径仍多套并存 | MediaMTX 主链外还有 legacy 组件 | 运维、资源和故障定位复杂 | P2 |
| INS-15 | Web token 存 localStorage | client.ts 明确存 JWT | XSS 后 token 暴露面较大 | P1/P2 |
| INS-16 | 云平台生产 SLO/HA/备份证据不足 | Compose/MVP 较完整，量产门仍待补 | 大规模运维风险 | P2 |

### 12.3 Inspection Executor 应是什么

建议在现有 omni-inspection 仓内新增一个 C++ 机器人进程，而不是另建仓库。

职责：

- 提供 CapturePhoto、Record Action、Recognize；
- 唯一持有巡检相机/云台/本地模型资源锁；
- 先写临时文件，fsync 后原子 rename；
- 计算 sha256、size、mime、capture timestamp；
- 绑定 mission/checkpoint/map/calibration/software identity；
- 写本地 durable evidence outbox；
- Edge 只负责上传和 ACK，不改变本地业务终态；
- 磁盘配额不足时 fail-fast；
- 支持 cancel、provider restart 和部分文件清理。

### 12.4 Edge 目标边界

Edge 应降级为北向 façade：

~~~text
Cloud command
 -> durable dedup
 -> typed Omni Mission/SLAM/Authority API
 -> local status/event
 -> QoS1 durable outbox
 -> Cloud ACK
~~~

Edge 不应再：

- 发布真实底盘速度；
- 调厂商姿态/运行模式；
- 自己执行 patrol；
- 自己选择 Nav2/SCAN Planner；
- 以缓存变量宣称地图已激活。

### 12.5 地图激活真实链

~~~text
download asset
 -> verify size/hash/signature
 -> verify robot/calibration compatibility
 -> import immutable MapBundle
 -> request SLAM localize(map_id/version)
 -> wait SlamStatus initialized+LOCALIZED
 -> wait TF authority ready
 -> verify RobotState map identity
 -> ACK completed
~~~

任一步失败都不能把云端地图标记为 active。

### 12.6 验收

- production profile 遇到 simulation adapter 直接拒绝启动；
- ROS 图中 Edge 不再拥有任何底盘速度或厂商模式接口；
- 断网重连后 ACK/event/evidence 元数据无丢失、无重复执行；
- telemetry 使用 canonical body odom，并携带 frame/stamp/map/freshness；
- 围栏在断网时仍能让 Bridge 最终输出零；
- 主视频链冻结为一套，fallback 明确且有首帧/断流/恢复指标。

## 13. rosdeck

### 13.1 已有边界

Rosdeck 已有：

- Expo/React Native App；
- rosbridge 与 Foxglove transport；
- teleop、任务、建图、导航、安全 UI；
- camera/pointcloud/map 等组件；
- WSS 认证、RBAC、审计 gateway；
- device pairing 数据存储。

### 13.2 缺失清单

| ID | 缺失 | 证据/现状 | 影响 | 优先级 |
| --- | --- | --- | --- | --- |
| APP-01 | Foxglove binary policy 解析 | App publish/service 用协议 binary；Gateway 把 binary 全按 CBOR dict decode | 真实 publish/service 会被 1003 拒绝或过滤 | P0 |
| APP-02 | 测试没有使用真实 App wire | Gateway E2E 发送 CBOR map，而非 Foxglove opcode frame | 测试通过掩盖主链不兼容 | P0 |
| APP-03 | SPKI pin 未执行 | pin 只存储，resolveLoginOptions 只传 user/token | 配对展示的证书固定没有安全效果 | P0/P1 |
| APP-04 | legacy 建图/导航控制 | /rosdeck/start_3d_mapping、/rosdeck/start_navigation，后者还混用 Bool/String | 与 typed SLAM/Mission 合同分叉 | P1 |
| APP-05 | legacy authority String | control-authority.ts 使用 /rosdeck/control_* | token/epoch/preemption 无法表达 | P0 |
| APP-06 | /vel_cmd fallback 仍可进生产 | teleop 保留 VBot 直连兼容 | 可能绕过 Bridge | P0 |
| APP-07 | receive allowlist 默认空=全放 | policy.py 明确 V1 default | viewer 可看到不必要 ROS 图信息 | P1 |
| APP-08 | admin allow all | 所有 op/topic/service 放行 | 高权限账号被盗影响面过大 | P1 |
| APP-09 | 断线/重连状态恢复证据不足 | 有 reconnect 基础，缺完整 task/authority snapshot reconcile | UI 可能显示旧 owner/任务 | P1 |
| APP-10 | App→Gateway→Foxglove→ROS 真 E2E 缺失 | transport 与 gateway 分开测试 | 关键协议问题未被 CI 捕获 | P0 |

### 13.3 Gateway 修正方向

Gateway 必须按 WebSocket subprotocol 解析：

- 登录帧可以是约定 JSON/CBOR；
- 登录完成后若 subprotocol 是 Foxglove，二进制帧必须按 Foxglove opcode 解析；
- clientMessage、serviceCallRequest 等必须提取 channel/service identity 后做策略判断；
- serverMessage、serviceCallResponse 必须按 subscription/service 映射做 receive policy；
- 不能把任意协议 binary 当 CBOR；
- rosbridge JSON/CBOR 与 Foxglove parser 必须分开。

### 13.4 验收

- 使用 App FoxgloveTransport 的真实 bytes 贯通 Gateway 和真实 foxglove_bridge；
- teleop publish、ControlAuthority service、Mission dispatch、status subscription 全部 E2E；
- pin 不匹配时连接在发送 token 前失败；
- production build 禁止 /vel_cmd direct fallback；
- reconnect 后重新读取 RobotState/MissionStatus/authority epoch，再开放操作；
- viewer/operator/admin 的收发 Topic/Service 都有最小 allowlist。

## 14. vbot_ros2_msgs

### 14.1 正确认识

该仓库包含 15 个供应商 ROS IDL 包、共 238 个 msg/srv/action 文件，但没有运行节点。它描述供应商合同，不实现：

- 底盘控制；
- SLAM；
- BMS；
- 相机驱动；
- 状态机；
- 安全策略。

当前 Omni 真正直接使用的主要合同只有：

- foxglove_msgs/CompressedVideo；
- function_msgs/SetRunMode；
- software_msgs/LowlevelAction。

因此“其余 12 个包没有使用”不能直接算成 12 个功能缺失。

### 14.2 真正的缺失

| ID | 缺失 | 影响 | 优先级 |
| --- | --- | --- | --- |
| VBOT-01 | 闭源 runtime 版本/hash 没进入完整 BOM | IDL 与运行库可能 ABI/语义不匹配 | P0/P1 |
| VBOT-02 | 硬件 capability discovery | 无法知道目标机实际提供哪些服务/topic | P1 |
| VBOT-03 | 权威 BMS source 未冻结 | Docking/RobotState 充电判断不可靠 | P1 |
| VBOT-04 | 真实速度入口 owner 未冻结 | Bridge 与 Edge /vel_cmd 可能并存 | P0 |
| VBOT-05 | 服务 QoS/timeout/error 语义验证不足 | 只编译通过不等于真机可用 | P1 |
| VBOT-06 | vendor→Omni converter/adapter 覆盖有限 | 上层仍可能依赖供应商字段 | P1 |
| VBOT-07 | IDL/runtime compatibility test | 升级供应商软件后可能静默破坏 | P1 |

### 14.3 验收

- 每台机器记录 vendor runtime 包版本、二进制 hash、IDL commit；
- 启动 preflight 检查必要 service/topic/type/QoS；
- Bridge 发布 capability snapshot；
- Edge/App 不直接消费厂商控制合同；
- 真机验证 BMS、运动、姿态和视频的权威 source。

## 15. omni_navi

### 15.1 当前已有边界

omni_navi 的职责是集成，不应增加另一个业务 Manager。当前已有：

- 11 仓架构和模块审计；
- manifest/lock；
- x86 导入、构建、测试脚本；
- candidate release 元数据；
- 接口矩阵和近期计划。

### 15.2 缺失清单

| ID | 缺失 | 当前证据 | 影响 | 优先级 |
| --- | --- | --- | --- | --- |
| NAVI-01 | omni_robot_bringup package | 当前没有全栈 launch/profile | 仍需各仓手动启动 | P1 |
| NAVI-02 | preflight | 无统一 frame/topic/QoS/资产/能力检查 | 配置错配只能运行后发现 | P0/P1 |
| NAVI-03 | systemd target 和关闭顺序 | Bridge 有部分 service，整栈没有统一 target | 重启/断电状态不可控 | P1 |
| NAVI-04 | 锁清单落后 | SLAM/Planner/TF/Rosdeck 当前 HEAD 与 lock 不同 | 审计事实与发布输入不一致 | P0 |
| NAVI-05 | release candidate 过期 | 仍是 2026-08-25，多个质量 gate pending | 不能代表当前全栈 | P1 |
| NAVI-06 | 全栈 artifact/BOM | 缺统一源码+IDL+vendor runtime+config+model hash | 无法重现一台已测试机器人 | P1 |
| NAVI-07 | Matrix E2E | 缺完整定位→任务→证据→返航→回充软件闭环 | 单仓测试无法放行 | P1 |
| NAVI-08 | Orin/S100 smoke | candidate 仍 pending | 目标板兼容未知 | P1 |
| NAVI-09 | 生产发布链 | SBOM、签名、provenance、rollback compatibility 不完整 | 量产发布风险 | P2 |
| NAVI-10 | 跨仓 contract CI | 没有所有 consumer 对同一 IDL fixture 的联合 gate | 接口升级易破坏其他仓 | P0/P1 |

### 15.3 omni_robot_bringup 应只包含

- robot profile schema；
- launch composition/remap；
- preflight；
- systemd target/service dependencies；
- BOM loader；
- graph audit；
- smoke tests；
- shutdown policy；
- 不包含业务状态机。

### 15.4 Preflight 至少检查

- robot model 与 adapter capability；
- vendor runtime/IDL/BOM；
- map/route/dock/calibration identity；
- canonical frame 和唯一 TF publisher；
- Topic type/QoS；
- 唯一速度 publisher 和唯一 SDK owner；
- authority provider；
- BMS/charge source；
- disk space/evidence quota；
- clock/time sync；
- required service/action readiness；
- production 禁止 simulation/legacy direct path。

### 15.5 验收

- 一条命令按 profile 启动整栈；
- preflight 不通过时所有自动速度保持禁用；
- 同一 BOM 可在 x86/Matrix、Orin、S100 追踪；
- Matrix 跑通完整软件链并注入进程 kill/断网/定位丢失；
- 目标板 smoke 与 artifact hash 写回 release record；
- 更新 lock 后联合构建测试通过，才允许形成新 candidate。

## 16. 跨模块缺口：不是某一个仓能单独修好

### 16.1 Authority 闭环

~~~text
Interfaces V2
 -> Bridge provider/single lease machine
 -> Mission C++ client
 -> Docking C++ client
 -> Rosdeck typed client
 -> Edge typed facade
 -> RobotState authority epoch
~~~

只改任意一端都不能完成。

### 16.2 Readiness 与最终运动许可

~~~text
SLAM initialized/state/freshness
 -> TF Manager structured ready
 -> RobotState gate details
 -> Planner/Docking/Mission precheck
 -> Bridge final motion gate
~~~

最终兜底必须在 Bridge，而不是假设每个上游永远正确。

### 16.3 资产闭环

~~~text
Cloud Map/Route/Dock/Calibration
 -> Edge download/verify
 -> immutable local Bundle
 -> SLAM activate/localize
 -> TF/RobotState identity
 -> Mission route validation
 -> Planner FollowRoute validation
 -> Docking dock validation
~~~

### 16.4 巡检证据闭环

~~~text
Mission checkpoint
 -> Inspection Executor
 -> atomic local artifact + hash
 -> Mission durable result
 -> Edge durable outbox/upload
 -> Cloud ACK
 -> retention/delete policy
~~~

### 16.5 SLAM 后端闭环

~~~text
Frontend keyframes
 -> loop backend
 -> optimized trajectory/map
 -> MapBundle version
 -> TF correction policy
 -> Planner/Bridge pause or smoothing
~~~

## 17. 推荐实施顺序

### Phase 0：先消除旁路和假成功

1. 冻结最小 Interfaces V2；
2. Bridge typed authority + single lease state machine；
3. TF/RobotState/Bridge 完整 readiness gate；
4. Planner 产品默认强制 ready，并真正校验 map identity；
5. 禁止 Edge 和 Rosdeck 的 /vel_cmd direct production path；
6. 修复 Foxglove Gateway binary parser；
7. production profile 禁止 simulation fallback；
8. 更新 omni_navi lock 到实际被审计提交。

### Phase 1：把业务运行时做实

1. Mission C++ pure core + store + async ROS；
2. Docking C++ pure core + async ROS；
3. Inspection Executor；
4. Undock→Mission→ReturnToDock→Dock 全链；
5. omni_robot_bringup/preflight/systemd；
6. Matrix E2E 和故障注入。

### Phase 2：补真实感知与算法闭环

1. Dock relative observation/contact/obstacle/BMS；
2. SLAM 离线后端、回环、图优化和 MapBundle；
3. Planner 地形/负障碍/动态障碍/全局 reroute；
4. Dog/VBot 全传感器外参审核；
5. Edge QoS1、mTLS、outbox、真实地图/位姿。

### Phase 3：在线优化和量产硬化

1. SLAM 在线后端 correction；
2. 多会话地图更新；
3. 24/72 小时 soak；
4. HIL、目标板性能和实时预算；
5. SBOM、签名、provenance、A/B/rollback；
6. 多 dock、多机器人和高级智能。

## 18. 近期工作包建议

| 工作包 | 主要输出 | 前置 | Exit |
| --- | --- | --- | --- |
| CONTRACT-V2 | Authority/readiness/asset/evidence 最小 V2 | 无 | 所有 consumer 生成/fixture 通过 |
| BRIDGE-GATE | typed lease + 最终 motion gates | CONTRACT-V2 | 任一 gate 失败按 deadline 零速 |
| MISSION-CPP | C++ core/store/ROS parity | CONTRACT-V2 | golden+crash+launch tests |
| DOCK-CPP | C++ core/providers/ROS parity | CONTRACT-V2 | golden+cancel+Matrix software loop |
| PAYLOAD | Inspection Executor | CONTRACT-V2 | photo/record/recognize 原子证据 |
| EDGE-FACADE | 删除旁路，typed facade，QoS1/outbox | BRIDGE-GATE | 断网不丢不重执行 |
| SLAM-BACKEND-A | 离线 keyframe/loop/graph/map | TF correction schema 可先冻结 | 优化 MapBundle 和精度报告 |
| PLANNER-PRODUCT | map gate、terrain/dynamic/global recovery | readiness+MapBundle | 场景回归门通过 |
| BRINGUP | profile/preflight/systemd/BOM | 主要 runtime RC | 一条命令+整机 smoke |
| DOCK-HW | relative/contact/obstacle/endurance | DOCK-CPP | 50–100 次基线 |

## 19. 放行矩阵

| 能力 | 当前 | 软件 RC | 真实试点 | 量产候选 |
| --- | --- | --- | --- | --- |
| SLAM 前端 | 有 | 固定数据集回归 | 目标场景精度 | 长时/退化/多机型 |
| SLAM 后端 | 无 | 离线后端可选 RC | 闭环路线必须 | 在线/多会话按需求 |
| Planner | 局部/路线跟随 | map/readiness gate | terrain/dynamic 场景 | 性能/SLO/HIL |
| Authority | legacy String | typed V2 | 全入口唯一 | SROS2/形式化故障验证 |
| Mission | Python pure core | C++ parity | 完整巡检/返航 | soak/恢复/迁移 |
| Docking | Python 全局 pose 原型 | C++ Matrix 软件闭环 | 真实相对感知+耐久 | 多机型/维护指标 |
| Inspection | provider 缺失 | C++ Executor | 真实证据上传 | 配额/加密/长期留存 |
| Edge | 有旁路/仿真风险 | typed façade | QoS1/mTLS/outbox | fleet SLO |
| App/Gateway | UI 有、binary 风险 | 真 E2E | pin/重连/安全 UX | 最小权限/审计运营 |
| Bringup/BOM | 缺 | profile+preflight | 目标板 smoke | 签名/回滚/可复现 |

## 20. 最终判断

按模块逐个看，最重要的不是把 TODO 数量做少，而是建立以下五条唯一事实链：

1. **位姿事实链**：SLAM → TF Manager → RobotState；
2. **运动事实链**：App/Mission/Docking candidates → Bridge → Vendor SDK；
3. **任务事实链**：Cloud/App → Mission → Planner/Payload/Docking；
4. **资产事实链**：Map/Route/Dock/Calibration identity 在每个执行层一致；
5. **证据事实链**：真实传感器产物 → 本地 hash/outbox → Cloud ACK。

当前最大的模块级投入是：

- omni_slam：补后端和回环，而不是继续只加强前端启动脚本；
- omni_docking：C++ 重构，同时补真实末端感知和物理成功证据；
- omni_mission_manager：C++ 重构并修正异步/持久化边界；
- omni_robot_bridge：完成 typed authority 和最终运动 gate；
- omni-inspection：补 Inspection Executor，并把 Edge 从控制 owner 改成 typed façade；
- omni_navi：把所有模块组合成可重复启动、可验证、可发布的整机。

只有这些边界闭合后，现有的单模块能力才会成为完整产品能力。

## 21. 关键结论的源码证据定位

本节不是完整文件清单，而是为容易产生争议的判断提供复核入口。行号会随代码变化，复核时应以符号和行为为准。

### 21.1 SLAM

| 结论 | 证据文件/符号 |
| --- | --- |
| FAST-LIO 使用 ikd-tree 和迭代滤波前端 | omni_slam/FAST_LIO/src/laserMapping.cpp；ikdtree、ICP and iterated Kalman filter update |
| prior-map 定位把先验 PCD 建入 ikd-tree | omni_slam/FAST_LIO/src/laserMapping.cpp；locate_in_prior_map 分支 |
| ICP 是初始 map→LiDAR 对齐 | omni_slam/icp_relocalization/src/icp_node.cpp；发布 icp_result 后成功退出 |
| ICP seed 被归一为 tracking 初始位姿 | omni_slam/FAST_LIO/src/laserMapping.cpp；initial_pose_cbk |
| 没有图优化依赖 | omni_slam/FAST_LIO/CMakeLists.txt、omni_slam/icp_relocalization/CMakeLists.txt；无 GTSAM/Ceres |
| MapStore 主要存 map.pcd 和 manifest.json | omni_slam/omni_slam_manager/omni_slam_manager/map_store.py |

### 21.2 TF Manager

| 结论 | 证据文件/符号 |
| --- | --- |
| ready 不检查 initialized/state | omni_tf_manager/src/omni_tf_manager_node.cpp；computeReady |
| slam_state 只记录/诊断 | 同文件；slamStatusCallback、diagnosticsTimerCallback |
| ICP 默认不允许再次初始化 | 同文件；icpPoseCallback、allow_map_reinitialization |
| identity alias 只改 metadata | omni_tf_manager/include/omni_tf_manager/sensor_frame_alias.hpp |
| VBot 配置/文档 shadow-authority 漂移 | omni_tf_manager/config/omni_vbot_dog.yaml 与 omni_tf_manager/README.md |

### 21.3 Planner

| 结论 | 证据文件/符号 |
| --- | --- |
| FollowRoute Goal 虽有 map identity | omni_robot_interfaces/action/FollowRoute.action |
| server 未校验 map_id/map_version | omni_planner/src/planner/plan_manage/src/follow_route_server.cpp；handleGoal、handleAccepted |
| 路径执行只把 path/mission/route 传入 FSM | 同文件；startFollowRoute 调用 |
| 产品 launch 默认不要求 TF ready | omni_planner/src/planner/plan_manage/launch/run.launch.py；require_tf_ready default |
| GlobalPathPublisher 是目标/waypoint 参考线发布器 | omni_planner/src/planner/plan_manage/src/global_path_publisher.cpp |
| 当前地图是滑动 3D occupancy grid | omni_planner/src/planner/plan_env/include/plan_env/grid_map.h |

### 21.4 Bridge 与 Interfaces

| 结论 | 证据文件/符号 |
| --- | --- |
| authority 运行时仍是 String topic | omni_robot_bridge/src/bridge_node.cpp；control_command/control_status |
| typed ControlAuthority 目前只有 IDL | omni_robot_interfaces/srv/ControlAuthority.srv 与 Bridge 源码对照 |
| motion_authorized 只看 E-stop+lease | omni_robot_bridge/include/rosdeck_robot_bridge/robot_state_aggregator.hpp；build |
| navigation/docking 是 Twist | omni_robot_bridge/src/bridge_node.cpp；cmd_vel_navigation、cmd_vel_docking |
| final seam 是 ROS Topic | omni_robot_bridge/include/rosdeck_robot_bridge/cmd_vel_arbiter.hpp；kFinalTopic |
| 姿态/locomotion 仍有 String façade | omni_robot_bridge/src/bridge_node.cpp；posture_command、locomotion_command |

### 21.5 Docking

| 结论 | 证据文件/符号 |
| --- | --- |
| Python core 的状态和 fail-closed 行为 | omni_docking/omni_docking/docking_core.py |
| cancel property 被按函数调用 | omni_docking/omni_docking/docking_node.py；_run_op |
| frame 错配只 warning | 同文件；_on_pose |
| 默认 legacy frame/pose | omni_docking/config/docking_params.yaml |
| authority 是 String 协议 | omni_docking/omni_docking/authority.py |
| 最终成功主要靠 pose+BMS | docking_core.py；PH_SERVING、PH_WAITING_CHARGE |
| 真机接触/障碍/耐久仍是 TODO | omni_docking/docs/TODO.md |

### 21.6 Mission

| 结论 | 证据文件/符号 |
| --- | --- |
| Future.wait_for_future 调用 | omni_mission_manager/omni_mission_manager/mission_manager_node.py；authority 与 dock config 调用 |
| Action goal 使用 goal_handle.goal | 同文件；_execute_cb、_return_cb |
| restart 后 active 变 INTERRUPTED | omni_mission_manager/omni_mission_manager/state_machine.py；recover |
| route 是文本+sidecar | omni_mission_manager/omni_mission_manager/route_store.py |
| payload 只有 clients | mission_manager_node.py；photo/record/recognize clients |
| SQLite 工程化缺口由仓库确认 | omni_mission_manager/docs/TODO.md |

### 21.7 Inspection Edge/Cloud

| 结论 | 证据文件/符号 |
| --- | --- |
| S100 直接发 /vel_cmd | omni-inspection/edge-agent/config/agent.s100.yaml |
| S100 直接调用厂商服务 | omni-inspection/edge-agent/src/s100_ros2_robot_adapter.cpp |
| 未识别/未编译 adapter 时退回 simulation | omni-inspection/edge-agent/src/main.cpp；adapter 创建分支 |
| map activate 只缓存 identity | omni-inspection/edge-agent/src/nav2_navigation_adapter.cpp；activateMap |
| telemetry pose 写死零 | omni-inspection/edge-agent/src/main.cpp；telemetryJson |
| MQTT publish 为 QoS 0 | omni-inspection/edge-agent/src/mqtt_client.cpp；publish 使用 0x30 |
| geofence 当前主要生成云端 alarm | omni-inspection/backend/internal/service/alarm.go、geofence.go |
| Web JWT 存 localStorage | omni-inspection/web-console/src/api/client.ts |

### 21.8 Rosdeck

| 结论 | 证据文件/符号 |
| --- | --- |
| App publish 是 Foxglove binary opcode frame | rosdeck/lib/foxglove-transport.ts；publish |
| App service call 是 Foxglove binary frame | 同文件；callService |
| Gateway 把 binary 统一按 CBOR decode | rosdeck/robot/omni_ws_gateway/omni_ws_gateway/gateway.py；_decode_frame |
| Gateway E2E 使用 CBOR map | rosdeck/robot/omni_ws_gateway/test/test_gateway_e2e.py；send_cbor |
| pairing pin 只被存储 | rosdeck/stores/usePairingStore.ts |
| 连接只带 user/token | rosdeck/stores/useRosStore.ts；resolveLoginOptions |
| legacy mapping/navigation Topic | rosdeck/components/MappingControl.tsx、NavigationControl.tsx |

### 21.9 VBot 与 Navi

| 结论 | 证据文件/符号 |
| --- | --- |
| VBot 仓是 15 个纯 IDL 包 | vbot_ros2_msgs 各 package.xml/CMakeLists.txt |
| 当前直接引用集中在三个合同 | Bridge、Edge、Rosdeck 对 CompressedVideo/SetRunMode/LowlevelAction 的引用 |
| lock 落后于部分当前 HEAD | omni_navi/manifests/omni_navi.lock.repos、omni_full_stack.lock.repos 与第 2 节基线对照 |
| candidate 多个 gate 尚 pending | omni_navi/releases/2026-08-25-candidate.yaml |
| 当前无完整 bringup package | omni_navi 仓库目录与 docs/INTEGRATION_TODO.md 的 REL-03 |
