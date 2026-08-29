# Omni 跨模块接口矩阵

> 审计基线：2026-08-28 当前工作区
>
> 目标：让每条关键 Topic、Service、Action、TF、文件资产和北向协议都能回答“谁生产、谁消费、当前是否接通、失效时怎么办”。

## 1. 状态标识

| 标识 | 含义 |
| --- | --- |
| **已接通** | Provider 和 consumer 都存在，源码默认名能够对上；仍不代表真机已验证 |
| **部分接通** | 两端存在但类型/frame/QoS/语义/profile 或部署尚未闭环 |
| **缺 Provider** | Client/IDL 已存在，当前没有产品实现 |
| **断链** | 双方预期对接，但当前实现不兼容或必经步骤会失败 |
| **遗留** | 兼容路径，允许迁移期存在，不得成为新依赖 |
| **目标** | 架构要求，代码尚未实现 |

## 2. 产品状态 Topic

| Topic | 类型 | QoS/频率 | Producer | Consumer | 现状 |
| --- | --- | --- | --- | --- | --- |
| `/omni/robot_state` | `omni_robot_interfaces/RobotState` | Reliable + Transient Local，约 1 Hz/变化时 | Bridge | Mission、Docking、Rosdeck、Edge（目标） | **已接通但语义偏弱**：`motion_authorized` 未含完整门控 |
| `/omni/slam/status` | `omni_tf_manager/SlamStatus` | Reliable + Transient Local heartbeat | SLAM Manager | TF Manager、Bridge；Mission 间接从 RobotState | **已接通/所有权泄漏** |
| `/omni/tf_manager/ready` | `std_msgs/Bool` | Reliable + Transient Local | TF Manager | Planner；Bridge/Docking 目标 | **部分接通**：Planner launch 可要求；ready 未严查 initialized/state |
| `/omni/mission/status` | `MissionStatus` | Reliable + Transient Local，depth 1 | Mission | Bridge、App、Edge | **已接通**，但 Mission ROS action wiring 有阻塞 |
| `/omni/mission/events` | `MissionEvent` | Reliable + Volatile，depth ≥10 | Mission | App、Edge、审计 | **已接通**；durable source 为 SQLite |
| `/omni/mission/checkpoint_results` | `CheckpointResult` | Reliable + Transient Local | Mission | App、Edge | **部分接通**：结果机制有，载荷 provider 缺失 |
| `/omni/docking/status` | `DockStatus` | Reliable + Transient Local，约 1 Hz | Docking | Mission/App/Edge | **已接通**到 ROS 层；真机末端观测缺失 |
| `/battery_state` | `sensor_msgs/BatteryState` | 配置/周期状态 | Bridge adapter | Docking、App/Edge | **已接通**；来源按 Zsi/VBot profile 不同 |
| `/diagnostics` | `diagnostic_msgs/DiagnosticArray` | Reliable/周期 | TF、Bridge 等 | 运维/App/Edge | **部分接通**：多个 producer 合法，需按 hardware_id/name 聚合 |

### 2.1 `SlamStatus` 关键字段

| 字段 | 语义 | 正确 consumer 行为 |
| --- | --- | --- |
| `mode` | STOPPED/MAPPING/LOCALIZATION | mode 与 state 组合验证，未知值 fail-closed |
| `state` | STARTING、MAPPING、MAP_READY、RELOCALIZING、LOCALIZED、DEGRADED、LOST、STOPPING、ERROR 等 | 自动导航只接受 fresh LOCALIZED |
| `initialized` | 本 session 算法和遥测已真正就绪 | TF ready/RobotState 必须使用，当前未完全使用 |
| `map_id/version/checksum` | 当前地图身份 | 与 route/dock/mission 绑定 |
| `lidar/imu/odom_age_ms` | 各遥测 freshness | 超限撤销 ready |
| `fitness_score` | ICP score，越低越好 | 需结合配置阈值，不单独当 localized |
| `pose_jump_count` | 当前 session 跳变计数 | 诊断/降级依据 |
| `status_sequence` | heartbeat 序列 | 监测 publisher reset/stale |

## 3. 状态估计、TF 和传感器 Topic

| Topic/TF | 类型/表达 | Producer | Consumer | 现状/约束 |
| --- | --- | --- | --- | --- |
| Vendor LiDAR topic | 厂商点云 | driver | TF sensor relay | 原始名称按 profile；header 必须真机采集验证 |
| Vendor IMU topic | 厂商 IMU | driver | TF sensor relay | 同上 |
| `/omni/sensors/lidar/points` | PointCloud2/custom Livox input | TF relay | FAST-LIO/ICP | **部分接通**：identity alias 不做数值变换 |
| `/omni/sensors/imu/data` | IMU | TF relay | FAST-LIO | SensorDataQoS 必须兼容 |
| `/omni/sensors/depth/image` | Image | TF relay | Planner depth path/inspection | profile 可选 |
| `/omni/sensors/rgb/image/compressed` | CompressedImage | TF relay | inspection/video | profile 可选 |
| `/state_estimation` | Odometry，`T_odom_tracking` | FAST-LIO | TF Manager | **已接通**；FAST-LIO 必须 `publish.tf_en=false` |
| `/icp_result` | Odometry/Pose，`T_map_icp_sensor` | ICP | TF Manager | **已接通**；默认每 localization session 接受一次 alignment |
| `/cloud_registered_global` | PointCloud2 in map | SLAM global publisher | Planner | **已接通/高频 QoS 需实测** |
| `/omni/tf_manager/body_odom` | Odometry in odom | TF Manager | 调试/局部 consumer | **已接通** |
| `/omni/tf_manager/body_odom_global` | Odometry in map | TF Manager | Planner；Mission/Docking 目标 | **已接通到 Planner**；Mission/Docking 默认仍旧 topic |
| `/state_estimation_global` | Odometry | 旧 SLAM/兼容链 | Mission、Docking | **遗留**；目标切到 global body odom |
| `/tf_static` | fixed body/sensor edges | TF Manager authority | 全图 | 一个 child 只能有一个 authority |
| `/tf` `map→odom` | 动态 transform | TF Manager authority | Planner/Docking/App | mapping identity；localization 来自 ICP normalization |
| `/tf` `odom→base` | 动态 transform | TF Manager authority | 全图 | 来自 FAST-LIO tracking pose + extrinsic |

### 3.1 Canonical frame

```text
omni_map
└── omni_odom
    └── omni_base_link
        ├── omni_imu_link
        │   └── omni_lidar_link
        ├── omni_depth_camera_link
        │   └── omni_depth_camera_optical_frame
        └── omni_rgb_camera_link
            └── omni_rgb_camera_optical_frame
```

当前 Route/Dock 默认 `lio_map`，Mission/Docking pose 默认 `/state_estimation_global`。迁移必须同时处理 frame ID、Topic、资产 metadata 和测试，不能只 remap Topic。

## 4. Planner 数据面

Launch 中的相对名会在节点 namespace/remap 后展开；下表写产品默认/稳定语义。

| 接口 | 类型 | Producer | Consumer | QoS/安全语义 |
| --- | --- | --- | --- | --- |
| `/omni/navigation/follow_route` | `FollowRoute` Action | Scan Planner | Mission | 单 active，mission ID 去重，可 cancel |
| `body_pose` remap→`/omni/tf_manager/body_odom_global` | Odometry | TF Manager | Planner FSM、Controller | SensorDataQoS；默认 0.30 s timeout |
| `sensor_pose` remap→global body odom | Odometry | TF Manager | Grid map | SensorDataQoS |
| cloud remap→`/cloud_registered_global` | PointCloud2 | SLAM | Grid map | SensorDataQoS；`real_cloud_is_world=true` |
| depth remap→camera depth | Image | camera | Grid map | 仅 depth profile |
| `tf_ready` remap→`/omni/tf_manager/ready` | Bool | TF Manager | Planner FSM | Reliable + Transient Local；产品应强制 require |
| `initial_path` | `nav_msgs/Path` | Mission/GlobalPathPublisher | Planner FSM | Reliable + Transient Local；mode 3 |
| `move_base_simple/goal` | PoseStamped | RViz/App tool | Planner FSM | mode 1，非 Mission 正式入口 |
| `planning/bspline` | `scan_planner_msgs/Bspline` | Planner FSM | Closed-loop controller | Reliable + Transient Local，depth 1；旧轨迹风险由 heartbeat identity 消除 |
| `planning/planner_heartbeat` | `PlannerHeartbeat` | Planner FSM，20 Hz | Controller | Reliable + Volatile，默认 0.40 s timeout |
| `planning/go2_execution_frozen` | Bool | Controller | Planner FSM | 对齐/冻结反馈，避免 Planner 误判进度 |
| `cmd_vel` remap→`/scan_planner/cmd_vel` | Twist | Closed-loop controller | Bridge arbiter | 当前产品 navigation candidate；目标改 `/omni/cmd_vel/navigation` |
| `planning/local_path` | Path | Controller | 可视化/调试 | 非控制合同 |
| `planning/controller_target` | PoseStamped | Controller | 可视化/调试 | 非控制合同 |

Heartbeat 和 B-spline 必须同时匹配 `traj_id + trajectory_start_time`；只按 traj_id 匹配会在 Planner 重启复用 ID 时执行旧轨迹。

## 5. 运动控制与安全 Topic/Service

### 5.1 Candidate 和最终速度

| 接口 | 类型 | 唯一 Producer | Consumer | 当前状态 |
| --- | --- | --- | --- | --- |
| `/omni/cmd_vel/teleop` | TwistStamped | Rosdeck/Foxglove 受控 App 入口 | Bridge | **已接通**；旧 Edge 不应成为第二 producer |
| `/scan_planner/cmd_vel` | Twist | Closed-loop controller | Bridge | **已接通/遗留命名** |
| `/omni/cmd_vel/navigation` | 目标 TwistStamped | Planner | Bridge | **目标**，尚未实现 |
| `/omni/cmd_vel/docking` | Twist | Docking | Bridge | **已接通** |
| `/omni/cmd_vel/final` | Twist | Bridge arbiter | Bridge Zsi adapter | **内部 seam**，部署需禁止外部 publisher/subscriber 绕行 |
| Vendor `/vel_cmd` 或 SDK call | vendor | Bridge adapter | 底盘 | **唯一出口目标**；Edge 当前违例 |

Bridge receipt watchdog 默认约 250 ms。正式部署应检查每个 candidate publisher count=1、E-stop publisher count=1、final publisher count=1。

### 5.2 Safety

| 接口 | 类型 | Provider/Producer | Client/Consumer | 语义 |
| --- | --- | --- | --- | --- |
| `/omni/safety/estop` | Bool heartbeat/latch | Safety Supervisor | Bridge arbiter | fresh 且唯一；失联 fail-closed |
| `/omni/safety/estop_request` | Bool | 硬件/外部安全源 | Safety Supervisor | true 可锁存；false 不得清 latch |
| `/omni/safety/supervisor_status` | String | Safety Supervisor | App/运维 | 兼容观测，业务不应解析成新合同 |
| `/omni/safety/arm_supervisor` | `std_srvs/Trigger` | Safety Supervisor | App/运维 | 先 arm |
| `/omni/safety/latch_estop` | Trigger | Safety Supervisor | App/硬件适配 | 显式锁存 |
| `/omni/safety/reset_estop` | Trigger | Bridge | App/运维 | supervisor healthy/armed 后才允许 reset |
| `/omni/cmd_vel/arbiter_status` | String | Bridge | App/运维 | selected/reject diagnostics，遗留字符串 |

### 5.3 Authority

| 接口 | 类型 | Provider | Client | 状态 |
| --- | --- | --- | --- | --- |
| `/omni/control/authority` | `ControlAuthority` Service | **应为 Bridge** | Mission、Docking、App gateway | **缺 Provider/断链** |
| `/rosdeck/control_command` | String Topic | client 发布，Bridge 消费 | App、Docking | **遗留已实现** |
| `/rosdeck/control_status` | String Topic | Bridge | App、Docking | **遗留已实现** |

当前 payload 是 `acquire|heartbeat|release:<client_id>`，默认 5 s lease。Typed V1 没有 token/epoch/release ack，V2 应补齐。迁移时 typed/legacy façade 必须共享同一内部 lease state，不能形成两位 owner。

## 6. Mission、Docking 和巡检 Action/Service

### 6.1 Mission provider

| 名称 | 类型 | Provider | Client | 状态/备注 |
| --- | --- | --- | --- | --- |
| `/omni/mission/execute` | `ExecuteInspection` Action | Mission | ROS 内部 client | **节点实现存在，wiring 风险** |
| `/omni/mission/dispatch` | `DispatchMission` Service | Mission | Rosdeck/Edge | Fire-and-forget；同一状态机 |
| `/omni/mission/control` | `MissionControl` Service | Mission | App/Edge | pause/resume/cancel，幂等 |
| `/omni/routes/list` | `ListRoutes` Service | Mission | App/Edge | 只列验证过的文件 |
| `/omni/mission/results` | `GetCheckpointResults` Service | Mission | App/Edge | SQLite durable history |
| `/omni/mission/return_to_dock` | `ReturnToDock` Action | Mission | App/低电策略 | 全局腿+末端腿+充电 |

Mission callback 当前存在 `goal_handle.goal`（应为 `.request`）和非 rclpy Future API 调用，故不能把“server 对象创建成功”当作 Action 链可用。

### 6.2 Planner/Docking provider

| 名称 | 类型 | Provider | Client | 状态/备注 |
| --- | --- | --- | --- | --- |
| `/omni/navigation/follow_route` | `FollowRoute` Action | Planner | Mission | **实现完整度高**；仍需 ROS 图 E2E |
| `/omni/docking/dock` | `Dock` Action | Docking | Mission/App | **行为实现，ROS cancel bug，真机感知缺** |
| `/omni/docking/undock` | `Undock` Action | Docking | Mission/App | 同上 |
| `/omni/docking/config` | `GetDockConfig` | Docking | Mission | **已实现** |
| `/omni/docking/verify_charge` | `VerifyCharge` | Docking | Mission/App | **已实现**，fresh BMS gate |

### 6.3 Inspection provider

| 名称 | 类型 | 期望 Provider | Client | 状态 |
| --- | --- | --- | --- | --- |
| `/omni/capture/photo` | `CapturePhoto` Service | `omni_inspection_executor` | Mission | **缺 Provider** |
| `/omni/capture/record` | `StartRecord` Service | Executor | Mission | **缺 Provider**；V2 宜 Action |
| `/omni/recognize` | `Recognize` Service | Executor | Mission | **缺 Provider** |

服务成功必须表示证据已在本地完成落盘并可按 path/hash 查到，而不是“已触发相机”。

## 7. SLAM 控制面

| 名称 | 类型 | Provider | Client | 前置/终态 |
| --- | --- | --- | --- | --- |
| `/omni/slam/start_mapping` | `StartMapping` Service | SLAM Manager | bringup/运维 | 创建 session，启动 FAST-LIO |
| `/omni/slam/stop_mapping` | `StopMapping` Service | SLAM Manager | bringup/运维 | 可拒绝丢弃未保存地图 |
| `/omni/slam/save_map` | `SaveMap` Action | SLAM Manager | bringup/运维 | FAST-LIO save→import→checksum→immutable version |
| `/omni/slam/start_localization` | `StartLocalization` Action | SLAM Manager | bringup/Mission/Edge 目标 | map hash→ICP→fresh odom→LOCALIZED |
| `/omni/slam/stop_localization` | `StopLocalization` Service | SLAM Manager | bringup/运维 | 整个 process group stop |
| `/map_save` | FAST-LIO 保存服务 | FAST-LIO | SLAM Manager | 内部接口，不对 App/Cloud 暴露 |

Map activate 的产品成功条件：map 文件存在且 hash 正确、StartLocalization 成功、fresh `SlamStatus.state=LOCALIZED`、`initialized=true`、TF ready=true。当前 Edge 只完成“缓存 identity”。

## 8. 遗留机器人命令

| 接口 | 类型 | 当前用途 | 处理策略 |
| --- | --- | --- | --- |
| `/rosdeck/start_3d_mapping` | String/Bool 兼容 | App→Bridge/VBot mapping script | 迁到 SLAM typed service/action |
| `/rosdeck/mapping_status` | String | 旧 UI 状态 | 迁到 SlamStatus |
| `/rosdeck/posture_command/status` | String | App/Edge→vendor posture | 迁到 Bridge typed service |
| `/rosdeck/locomotion_command/status` | String | run mode | 迁到 Bridge typed service |
| `/rosdeck/start_navigation` | Bool/String 冲突 | 旧 App navigation | 删除，改 Mission/Planner typed API |
| Vendor `/vel_cmd` | Twist/vendor | 旧 Edge/Planner bridge | 除 Bridge adapter 外禁止 |

## 9. 文件与持久化接口

| 资产/数据 | 默认位置/形态 | Owner | Consumer | 一致性要求 |
| --- | --- | --- | --- | --- |
| Map | `<map_root>/<map>/versions/v.../map.pcd + manifest` | SLAM Manager | ICP/Planner/Cloud sync | SHA256、immutable、atomic `current` |
| Route | `/var/lib/omni/routes/<id>.txt` + `.route.json` | Mission | Mission/Planner | map/frame binding、finite points、path traversal 防护 |
| Checkpoints | route 同名 sidecar JSON | Mission | CheckpointRunner | schema、point index、action bounds |
| Dock | `/var/lib/omni/docks/*.json` | Docking | Mission/Docking | map ID/version、frame、pose、approach distance |
| Mission DB | `/var/lib/omni/mission_manager/missions.db` | Mission | Mission/App query | transaction、idempotency、restart→INTERRUPTED |
| Evidence | 目标本地 spool | Inspection Executor | Mission/Edge uploader | temp→fsync→hash→rename、durable outbox |
| TF profile | `omni_tf_manager/config/*.yaml` | TF Manager | SLAM/Planner/bringup | robot model/serial、6DoF、verified alias、checksum |
| Release | `<prefix>/releases/<id>` + current/previous | deployment | systemd/run-prebuilt | manifest/SHA/signature、health check、atomic rollback |
| Gateway tokens | 本地 digest store | omni_ws_gateway | auth | SHA256、0600、atomic write |
| Gateway audit | JSONL rotated | gateway | 运维 | append-only metadata、retention |

## 10. Cloud↔Edge MQTT 接口

| 方向 | 类别 | 可靠性需求 | 当前偏差 |
| --- | --- | --- | --- |
| Edge→Cloud | heartbeat | 周期覆盖，允许丢单条 | 当前可用 |
| Edge→Cloud | telemetry/state | sequence/timestamp、latest cache + durable need-based | pose 可能 placeholder |
| Cloud→Edge | command | command ID、expiry、sequence、ACK、去重 | Edge wire QoS 主要为 0，不能仅依赖 MQTT QoS |
| 双向 | patrol/navigation | 长任务 accepted/progress/terminal 分离 | Edge 自有状态机与 Mission 重复 |
| 双向 | map activate | identity + hash + terminal localization result | 当前只缓存 identity |
| 双向 | OTA/config | version、checksum、batch state、rollback | 与机器人全栈 BOM 尚未统一 |
| 双向 | video | session/stream identity，不承载媒体本体 | 媒体走 SRT/RTSP/WebRTC |

PCD、录像和证据二进制不走 MQTT；通过 HTTP/object/media storage，并在 MQTT/DB 只传 identity、URI、hash 和状态。

## 11. App↔Gateway↔Foxglove

| 边 | 协议 | 身份/授权 | 当前状态 |
| --- | --- | --- | --- |
| App→Gateway | TLS 1.2+ WSS，JSON/CBOR login | token digest、role、lockout | **已实现** |
| Gateway→Foxglove | loopback WebSocket | 仅 Gateway 可达 | **已实现** |
| App publish/service | Foxglove binary frames | 应按 channel/service ID 做 policy | **断链风险**：Gateway 当 CBOR map 解码 |
| Gateway audit | JSONL metadata | role/op/topic/result | **已实现** |
| TLS SPKI pin | 配对保存 pin | 客户端应强制校验 | **部分接通/待真机验证** |

正式验收必须用实际 Rosdeck FoxgloveTransport，而不是测试专用 CBOR `{op,topic}` frame。

## 12. HTTP/WebSocket/Video 北向接口

| 接口 | Owner | Consumer | 边界 |
| --- | --- | --- | --- |
| REST `/api/...` | Inspection Backend | Web/外部系统 | JWT/RBAC/rate limit/audit |
| Backend WebSocket | Inspection Backend | Web Console | 实时事件；重连后先 snapshot |
| HTTP map upload | Backend Maps | Web/operator | PCD header/size/hash/complete |
| SRT ingest | Robot streamer→MediaMTX | MediaMTX | 长连接媒体，不走业务 API |
| WHEP/WebRTC | MediaMTX | Browser | 主低延迟播放路径 |
| RTSP | MediaMTX | Gateway/录制/运维 | 内网/鉴权 |
| MJPEG/snapshot | Python video gateway | Web/兼容 client | fallback，不是主实时链 |

## 13. QoS 基线

| 数据类型 | 建议 QoS | 原因 |
| --- | --- | --- |
| LiDAR/IMU/Image/high-rate odom | SensorDataQoS（Best Effort + Volatile，小 depth） | 降低积压，reader 必须与 writer 兼容 |
| Robot/SLAM/Mission/Dock latest state | Reliable + Transient Local，depth 1 | late join 获取最新状态 |
| Mission event | Reliable + Volatile，depth ≥10 | live transition；durable history 另存 |
| Planner B-spline | Reliable + Transient Local，depth 1 | late controller 获取候选，但须 heartbeat 授权 |
| Planner heartbeat | Reliable + Volatile，depth 1 | 不能 latched 伪装 fresh |
| Candidate cmd_vel | Best Effort/Volatile，depth 1 + receipt watchdog | 新命令覆盖旧命令，过期零速 |
| E-stop heartbeat | Reliable + Volatile，depth 1 + deadline | 丢失必须 fail-closed |

DDS compatibility 不能靠假设。CI 应启动真实 writer/reader 并检查 endpoint match、消息到达、deadline 和 transient behavior。

## 14. 当前最关键的断链

1. Mission→`/omni/control/authority`→Bridge：Bridge provider 缺失。
2. Mission Action callback/Future 等待：rclpy API 使用错误。
3. Docking Action cancel：把属性当方法。
4. Mission→capture/record/recognize：三个 provider 全缺。
5. Edge→vendor `/vel_cmd`/服务：绕过 Bridge 唯一控制面。
6. Edge map activate→SLAM/TF：只缓存 identity。
7. Rosdeck Foxglove binary→Gateway policy：协议表示不匹配。
8. TF ready→自动运动许可：initialized/state/freshness 未闭环。
9. `/state_estimation_global`/`lio_map`→canonical TF：资产和消费者未完成迁移。
10. `omni_navi`→全栈 bringup：不存在统一启动/关闭接线。

这些项关闭前，接口数量再多也不能构成“自动巡检整机已跑通”的证据。
