# Omni Navi 近期交付计划（三人团队）

> 重排日期：2026-08-26
> 原则：先形成唯一、安全、可执行的机器人本地链路，再继续 Planner 算法、Cloud 和运营功能。

## 1. 当前只保留三条主线

| 主线 | 负责人占位 | 目标 | 明确不包含 |
| --- | --- | --- | --- |
| A：整机架构与运动安全 | 负责人 A | 冻结接口；Bridge typed authority；定位/TF/Planner 运动 gate | Cloud 功能扩张、算法升级、完整 OTA |
| B：Mission Manager C++ | 负责人 B | 任务 core、事务存储、async ROS happy path | 一次完成全部真机故障/量产验收 |
| C：Docking C++ | 负责人 C | 硬件合同、控制 core、Matrix 安全闭环 | 无相对观测时宣称真机自动回充 |

每人每个 Iteration 只承担一个主要交付项。跨主线评审不另行计一个并行 Epic。

## 2. W35–W37 排期

### 2026 W35：架构和接口冻结

| Key | Status | Priority | Owner | Estimate | 交付物/验收 |
| --- | --- | --- | --- | ---: | --- |
| `PORT-01` | In Progress | P0 | 负责人 A | 8 | 架构/ADR 评审；最小 V2 `ControlAuthority`、`RobotState` readiness、`SlamStatus` 所有权和 QoS 合同合入接口仓，并通过生成/ABI 测试 |
| `MIS-01` | Todo | P0 | 负责人 B | 8 | Mission CMake/C++ skeleton、golden harness、状态机和持久化接口冻结 |
| `DOCK-01` | Todo | P0 | 负责人 C | 8 | Dock 硬件/末端感知合同、CMake/C++ skeleton、状态机与安全包络冻结 |

W35 Exit：支撑 W36/W37 的最小 V2 IDL 已合入 `omni_robot_interfaces`，生成代码和 ABI/constant gate 通过；其余接口进入明确版本化清单。任何仓库不再自行定义 frame、authority 或 cancel 语义。

### 2026 W36：核心实现

| Key | Status | Priority | Owner | Estimate | 交付物/验收 |
| --- | --- | --- | --- | ---: | --- |
| `BR-01` | Todo | P0 | 负责人 A | 8 | Bridge 提供 typed authority；唯一 lease state machine；APP/MISSION/DOCKING 零速交接单测；提供 W37 共用 RobotState/readiness contract fixture |
| `MIS-04` | Todo | P0 | 负责人 B | 8 | Mission pure core、route/checkpoint、SQLite 原子事务、crash recovery 单测 |
| `DOCK-04` | Todo | P0 | 负责人 C | 8 | Docking pure core、geometry/config/charge、安全不变量及 property/fuzz tests |

W36 Exit：三条主线的 pure C++ 和 Authority 基础可以独立测试；W37 所需的 readiness/RobotState mock 与 contract fixture 已冻结。Python 仍是默认运行时，不做大爆炸切换。

### 2026 W37：ROS RC 和 Matrix 证据

| Key | Status | Priority | Owner | Estimate | 交付物/验收 |
| --- | --- | --- | --- | ---: | --- |
| `READY-01` | Todo | P0 | 负责人 A | 8 | TF/RobotState 按 initialized/state/freshness fail-closed；Planner 强制 ready；QoS endpoint test |
| `MIS-02` | Todo | P0 | 负责人 B | 8 | 基于 W36 contract fixture 的 C++ async ROS adapter；Dispatch→FollowRoute、cancel、authority/ready timeout launch tests |
| `DOCK-02` | Todo | P0 | 负责人 C | 8 | 基于 W36 contract fixture 的 C++ async ROS adapter；Matrix observation→dock、cancel/E-stop/lease-loss 零速测试 |

W37 三项是联合集成，不互相作为开周前置：B/C 先对 W36 fixture 开发，A 完成真实 TF/RobotState/Planner 聚合后统一替换 mock。Exit 只定义为 **C++ parity RC + Matrix 软件闭环**，不是量产回充，也不是完整真实巡检产品。

## 3. W37 之后的必要工作（Backlog）

以下工作重要，但不与前三周主线争抢人力。完成 RC 后按依赖顺序拉入新 Iteration。

### P1：真实巡检试点前必须完成

1. `REL-03`：在 `omni_navi` 新增 `omni_robot_bringup` profile/launch/systemd/preflight/BOM；不新增业务 Manager。
2. `MIS-03`：Pause/Resume、RTD 零速租约交接、Payload、完整 fault paths，切换默认 C++。
3. `DOCK-03`：实现真机 relative observation、contact/obstacle gate、标定和 50–100 次基线。
4. `EDGE-01`：Edge 删除 `/vel_cmd`、厂商 service、Nav2/patrol 本地执行；只桥接 typed Mission/SLAM/Authority。
5. `PAYLOAD-01`：一个 C++ Inspection Executor 提供 photo/record/recognize、原子证据文件和 hash。
6. `TF-04`：Dog/VBot 的 LiDAR/IMU/Depth/RGB 实际 Topic/header、完整 6DoF 和 CameraInfo 审核。
7. `REL-02`：锁定 BOM 的 x86/Orin/S100 联合构建、Matrix E2E 和目标板 smoke。

### P2：量产硬化

- MQTT mTLS、设备身份、QoS1、durable outbox 和重放去重；
- 证据断点上传、Cloud ACK 后删除、磁盘配额；
- SROS2/ROS 图 ACL、签名、SBOM、OTA A/B 和回滚；
- 24/72 小时 soak、进程 kill、断网、磁盘满、时钟异常和地图损坏；
- 地图/路线/标定资产同步、兼容迁移和运营指标。

### P3：可继续后置

- 多机任务优化、边缘 VLM、复杂报表；
- 不影响当前闭环的 App 体验增强；
- 与当前巡检链无关的模拟器和 vendor 示例构建；
- 非阻断性的旧命名清理。

## 4. 已确认且必须纳入上述 Epic 的缺陷

不再把每个发现都排成一个近期并行任务，以下缺陷分别并入对应 Epic：

| 缺陷 | 并入 |
| --- | --- |
| Mission 使用不存在的 `Future.wait_for_future()`、错误 Action/Pose API | `MIS-01/02` |
| Docking 参数未声明、cancel property 调用错误、yaw/frame 错误 | `DOCK-01/02` |
| Bridge 缺 typed authority，S100/VBot 没有统一最终速度链 | `BR-01` |
| TF shadow/initialized/state 可产生 ready 假阳性 | `READY-01` |
| canonical sensor writer Best Effort、reader Reliable 不匹配 | `READY-01` |
| Planner 产品默认 `require_tf_ready=false` | `READY-01` |
| Edge S100 默认 simulation patrol，可“机器不动任务成功” | `EDGE-01` |
| Edge map activate 只改缓存，不启动/验证定位 | `EDGE-01` |
| Capture/Record/Recognize 没有 provider | `PAYLOAD-01` |

## 5. 三人协作规则

- A 是接口/整机合并 owner，B/C 分别对 Mission/Docking 代码负责；
- 任何 IDL、authority、TF/frame、错误码、QoS 修改必须至少一位其他主线负责人 review；
- 每条主线保持一个可运行的短分支，按小 PR 合入，不建立长期大分支；
- 每项 8 SP 已包含跨线 review、CI 修复和集成返工，不另加隐形并行承诺；
- Python 运行时在 C++ launch/golden/fault tests 达标前不删除；
- 真机测试只从已锁定 SHA/BOM 构建，不使用开发目录的浮动 `main`；
- P0 进入 Iteration 后，非生产事故不得插入新的 P2/P3 工作。

## 6. RC 与量产的定义

### W37 RC

- typed authority 和 fail-closed readiness 有自动化测试；
- Mission/Docking C++ happy path、cancel 和主要 timeout 在 x86/Matrix 通过；
- 图中不存在第二个最终速度 publisher；
- 产物和接口 SHA 可追踪。

### 真机试点

- `omni_robot_bringup` 一条命令按 profile 启动完整栈；
- Dog/VBot 的 sensor header/外参经过现场审核；
- 短路线巡检、真实照片 hash、人工接管、定位丢失停车通过；
- Dock 有相对观测/接触/充电闭环，并完成低速批量基线。

### 量产候选

- x86、Orin、S100 使用同一不可变 BOM；
- 所有 artifact 有 checksum/provenance；
- 24/72 小时 soak 和故障注入通过；
- 安全、部署、回滚、标定和运维 runbook 完整。
