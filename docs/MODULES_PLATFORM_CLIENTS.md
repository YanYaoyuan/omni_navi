# 平台、边缘、视频与客户端模块详解

> 审计基线：2026-08-28 当前工作区
>
> 范围：`omni-inspection`、`rosdeck`、`vbot_ros2_msgs`、`omni_navi`
>
> 说明：本页既覆盖北向平台，也检查它们是否绕过机器人运行时安全边界。

## 1. 总体关系

```text
                    ┌──────── omni-inspection Cloud ────────┐
Web Console ─HTTPS─>│ Go Backend ─ PostgreSQL / Redis       │
                    │     ├─ WebSocket events               │
                    │     └─ MQTT commands/telemetry        │
                    └─────────────────┬──────────────────────┘
                                      │ MQTT/TLS（目标）
                                      v
                              C++ Edge Agent
                                      │ typed ROS facade（目标）
                                      v
                              Mission / Bridge / SLAM

Rosdeck Mobile App ─WSS─> omni_ws_gateway ─loopback─> Foxglove Bridge ─> ROS graph
```

Cloud 和本地 App 是两条独立北向路径：

- Cloud 适合任务下发、资产、告警、审计、证据和远程运维；
- Rosdeck 适合现场配对、状态观察、显式人工接管和本地任务操作；
- 两条路径最终都必须落到同一 Mission/Bridge 权威状态机，不能各自建立控制面。

## 2. `omni-inspection` 仓库总览

这是一个多技术栈 monorepo，而不是单一“巡检节点”：

| 子系统 | 语言/框架 | 部署位置 | 核心职责 |
| --- | --- | --- | --- |
| Backend | Go + Gin | Cloud/站点服务器 | REST、JWT/RBAC、业务、MQTT、WebSocket、持久化 |
| Edge Agent | C++17 | 机器人 | MQTT 会话、遥测、命令防重放、ROS/机器人/video adapter |
| Web Console | Vue + TypeScript | 浏览器 | 运维、任务、地图、视频、告警和资产 UI |
| Video Streamer | C++ + GStreamer | 机器人 | ROS 视频采集、编码适配、SRT/RTP 推流 |
| MediaMTX | 独立服务 | Cloud/站点 | RTSP/SRT/WebRTC/WHEP 媒体路由 |
| Video Gateway | Python | Cloud/站点 | MJPEG、快照、录像兼容 API |
| Pion Gateway | Go | 可选 | 旧/可选 WebRTC 信令媒体路径 |
| Protocols | JSON Schema/文档 | 两端共享 | MQTT payload 和 topic 合同 |
| Deploy | Compose/nginx/config | Cloud/边缘主机 | 数据库、broker、媒体、观测、反向代理 |

仓库名中的 inspection 同时覆盖“巡检平台”和“机器人边缘接入”，但当前还没有 ROS `omni_inspection_executor` provider；Mission 所需的 photo/record/recognize 并未由此仓库真正闭环。

## 3. Go Backend

### 3.1 启动装配

`backend/cmd/server/main.go` 负责创建并连接：

1. 配置和结构化日志；
2. PostgreSQL store/migrations；
3. 可选 Redis realtime cache；
4. MQTT client、订阅和 command ACK tracker；
5. WebSocket hub；
6. 领域 services；
7. Gin router、middleware、health/metrics；
8. 巡检 scheduler、离线 watcher、telemetry retention 等后台循环；
9. 信号驱动的有序 shutdown。

这是 modular monolith：领域代码分包，但以一个 server 进程部署。当前规模不需要拆成多个网络微服务。

### 3.2 HTTP 边界

API middleware 包含：

- JWT 登录/续期和用户身份；
- role/permission 检查；
- request ID、结构化错误；
- CORS、安全 header；
- IP/用户维度 rate limit；
- access/audit logging；
- health/readiness 和 Prometheus metrics；
- Swagger/OpenAPI 入口。

业务 handler 不应直接持有机器人长连接，而是调用 service，再由 service 写 store、发 MQTT 或广播 WebSocket。

### 3.3 领域服务

| Service 领域 | 主要职责 |
| --- | --- |
| Auth/User/Role | 用户、角色、权限、token 生命周期 |
| Robot | 机器人资产、在线状态、详情、遥测快照 |
| Control | 控制 session/token、授权、命令审计 |
| Video/Gimbal | 视频会话、流地址、云台请求 |
| Maps | PCD/metadata 上传、校验、complete、activate |
| Navigation | goal/route plan、导航命令和状态 |
| Patrol/Route/Task | 巡检路线、任务、事件和结果 |
| Scheduler | 定时任务生成、到期触发、重试 |
| Alarm | 规则评估、告警生命周期、联动录像/事件 |
| Recording | 录像索引、存储和回放 metadata |
| Geofence | 围栏配置和违规事件 |
| OTA | 软件包、批次、设备状态和回滚信息 |
| Maintenance | 保养计划、记录、提醒 |
| Event/Workorder | 事件处置和工单流转 |
| Knowledge | 知识库条目/附件 |
| Edge Config | 机器人边缘配置版本和下发 |

告警引擎能够在规则命中时创建事件并触发约 5 分钟录像；这种联动是平台业务，不应直接接管速度。

### 3.4 持久化

PostgreSQL 是 durable source。迁移表覆盖：

- users/roles/permissions；
- robots、telemetry、online/state；
- control sessions、commands、audit logs；
- maps、navigation plans/goals；
- patrol routes/tasks/events/results；
- alarms、events、workorders；
- videos、recordings；
- edge config、OTA batches/devices；
- geofences、maintenance；
- knowledge base；
- command queue/ACK。

Redis 用于在线/最新遥测等低延迟读；不可用时可退到内存/数据库路径，但不能把 Redis 数据当唯一审计记录。Telemetry 有定期清理策略，默认约保留 30 天；证据和审计 retention 要按业务另行定义。

### 3.5 MQTT 上下行

Backend 消费机器人 heartbeat、telemetry、state、task/nav/OTA 事件，更新 store/cache 并广播 WebSocket；下行发布 control、patrol、map、navigation、video、OTA 等命令，并以 command ID 跟踪 ACK 和离线队列。

正确的可靠性语义应由应用层 command identity + ACK + durable queue 保证，而不是仅依赖 MQTT QoS。

## 4. MQTT 协议与地图路径

### 4.1 Topic 类别

协议目录按 robot identity 组织：

- heartbeat/telemetry/state：设备周期上报；
- command：Cloud 发往设备；
- command ACK/result：设备确认接收和终态；
- task/patrol/navigation：长任务事件；
- video/OTA/config：子系统控制和状态。

Payload 使用 JSON schema 约束版本、robot ID、command/request ID、timestamp、sequence 和 data。

### 4.2 实际 QoS 偏差

文档建议关键 command 使用 QoS 1，但当前 Edge 的轻量 MQTT client 发布/订阅路径主要实现 QoS 0。即使 broker 接受订阅参数，也不能据此宣称端到端“至少一次”。因此：

- Cloud 必须允许 ACK timeout/retry；
- Edge 必须按 command ID/sequence 去重；
- 会引发物理动作的旧 command 过期后不得执行；
- 真正启用 QoS 1 前要补 PUBACK/packet retransmission 状态机和断线恢复测试。

### 4.3 地图二进制

PCD 本体不经 MQTT：

1. Web/API 创建上传并传 metadata；
2. HTTP 上传 PCD；
3. Backend 检查大小、PCD header、hash；
4. complete 后进入可激活状态；
5. activate 命令通过 MQTT 通知 Edge。

当前 Edge/Nav adapter 的 activate 只缓存 map ID/version/hash，没有下载/安装地图、调用 SLAM StartLocalization、等待 `SlamStatus LOCALIZED` 和 TF ready。因此 Cloud 显示“activated”不能解释为机器人已经定位成功。

## 5. C++ Edge Agent

### 5.1 运行结构

`edge-agent/src/main.cpp` 装配：

- 配置和日志；
- 原生 TCP MQTT 3.1.1 client；
- RobotAdapter；
- NavigationAdapter；
- SafetyGuard；
- VideoProcessController；
- heartbeat/telemetry 周期上报；
- command dispatch 和 ACK。

默认不依赖 ROS 编译，可运行 simulation adapter；ROS 2、Nav2、S100 和硬件视频 codec 均由编译选项选择。这种可移植性也带来风险：真机配置未显式选择 adapter 时，可能静默落到 simulation。

### 5.2 MQTT client

客户端手工实现 CONNECT/CONNACK、SUBSCRIBE、PUBLISH、PING 和 reconnect，优点是依赖少；代价是协议能力有限。当前没有完整 TLS/QoS1 持久会话证据，生产环境必须把 broker ACL、TLS、证书轮换和 replay test 纳入 gate。

### 5.3 SafetyGuard

远程运动命令在 adapter 前先检查：

- 当前 control grant/session 是否存在；
- token 是否匹配且未过期；
- command timestamp 是否在窗口内；
- sequence 是否严格递增；
- 速度是否为有限数并在配置上限内。

如果已经运动但约 500 ms 未收到新命令，hard-stop。这个 guard 是有价值的第二道输入校验，但它不能替代 Bridge 的最终 E-stop/authority/source watchdog。

### 5.4 RobotAdapter

#### Simulation adapter

在无 ROS build 下返回模拟状态和成功结果，用于开发。生产配置必须显式拒绝 simulation，否则“patrol 成功、机器人未移动”会成为假阳性。

#### S100 ROS 2 adapter

当前实现直接：

- 发布厂商 `/vel_cmd`；
- 调用 `SetRunMode`；
- 调用 `LowlevelAction`；
- 执行 stop/emergency/posture 等命令。

这与 `omni_robot_bridge` 的“唯一 SDK owner/最终速度出口”冲突。目标是把 Edge 改成 typed facade：

- task/patrol → Mission；
- navigation → Mission/Planner 的受控 API；
- manual control → typed ControlAuthority + teleop candidate；
- posture/emergency → Bridge typed service；
- 不再发布 `/vel_cmd` 或直接调用厂商服务。

### 5.5 NavigationAdapter

当前可选 `Nav2NavigationAdapter` 调用 `ComputePathToPose` 和 `NavigateToPose`，并维护 goal 状态；基础 adapter 也包含模拟 navigation/patrol。它未与本仓的 SCAN Planner `FollowRoute`、Mission route/checkpoint 语义统一。

产品必须选择单一导航业务入口。若 SCAN Planner 是正式路径，Edge 不应平行启动 Nav2 NavigateToPose 构成第二套导航状态机。

### 5.6 Patrol 和巡检动作

Edge patrol 当前以 detached thread 顺序执行 waypoint/inspection，并包含模拟等待/结果；这与 Mission Manager 的持久任务、检查点重试和幂等状态机重复。目标是 Edge 只翻译 Cloud command 并转发 Mission，任务终态由 Mission/Inspection Executor 回传。

### 5.7 Telemetry

CPU、内存、磁盘、温度和网络来自 `/proc`/`sysfs`；机器人业务状态来自 adapter。当前 pose 可能为零值 placeholder，因此平台地图上的实时位置不一定可信。正确来源应是 canonical global body odom/RobotState，并携带 frame、map identity 和 freshness。

## 6. 巡检载荷缺失与目标 Executor

Mission 已定义：

- `/omni/capture/photo`；
- `/omni/capture/record`；
- `/omni/recognize`。

当前仓库的视频流、录像和识别相关代码没有以这三个 ROS provider 的合同存在。建议在 `omni-inspection` 中新增单一 C++ `omni_inspection_executor` 进程：

1. 统一相机/编码器/模型连接；
2. 按 mission/checkpoint/request identity 建临时目录；
3. 完成 capture/record/inference；
4. fsync、计算 SHA256、原子 rename；
5. 返回 artifact/result metadata；
6. 写 durable upload outbox；
7. Edge 只上传，不能重做物理采集。

V1 的 StartRecord 是阻塞 Service，长录像容易占用 executor；V2 更适合 Action，以便 feedback/cancel/query by operation ID。

## 7. 视频子系统

### 7.1 机器人视频 streamer

Dog video streamer 支持：

- `foxglove_msgs/CompressedVideo`；
- `sensor_msgs/Image`/`CompressedImage` 等输入 adapter；
- 有界队列，积压时丢最旧帧；
- H.265 bitstream 解析/适配；
- 可选 S100 hardware H.265→H.264 转码；
- GStreamer `appsrc` 管线；
- RTP 或自定义 SRT 输出；
- pipeline bus error/EOS 监控与重启；
- 帧、丢帧、重启、延迟等 metrics。

当前 S100 配置倾向于板端转 H.264 后通过 SRT 发到 MediaMTX。

### 7.2 MediaMTX 主路径

MediaMTX 负责 SRT/RTSP ingest 和 WebRTC/WHEP/RTSP egress，减少自研媒体服务器职责。nginx/API 负责访问控制和业务 session，不应把原始公开推流地址当长期凭证。

### 7.3 兼容/可选路径

- Python video-gateway：RTSP 拉流后提供 MJPEG、snapshot、recording，简单但转码成本高；
- Go Pion gateway：旧的自研 WebRTC 路径；
- ffmpeg transcoder container：不支持目标 codec 时的兼容转码；
- LiveKit/Coturn 配置：可选部署，不等于默认链路。

主架构应只选择一条生产 WebRTC 路径，其他作为明确 fallback，避免同时拉同一 robot stream 造成带宽和编码资源翻倍。

## 8. Web Console

### 8.1 应用结构

Vue/TypeScript 单页应用通过 API client 和 WebSocket event client 连接 Backend。界面模块覆盖：

- Overview；
- Robots/assets；
- Patrol/tasks；
- Video；
- Maps/navigation；
- Devices/MQTT/Edge；
- Alarms/events/workorders；
- Recordings；
- Geofence；
- Users/roles/audit；
- Knowledge；
- OTA/maintenance（按权限和实现入口显示）。

UI 支持中英文本、暗色和响应式布局；功能可按角色过滤。前端隐藏按钮不能替代 Backend RBAC。

### 8.2 API 与实时状态

`api/client.ts` 统一 base URL、JWT、错误和各领域 request。WebSocket 接收 robot/telemetry/task/alarm 等事件，更新本地 view；断线后应重新获取 authoritative snapshot，再应用新事件，不能假设错过的事件会全部补发。

JWT 当前存 localStorage，生产部署要配合 CSP、短期 access token、refresh rotation 和 XSS 防护。

### 8.3 控制语义

Web 控制台面向 Cloud，经 MQTT 到 Edge，延迟和失联条件不同于本地 App。默认不应开放连续远程 teleop；若未来需要，必须经过明确产品安全评审、低 TTL command、typed authority、Edge guard、Bridge watchdog 和网络故障注入。

## 9. `rosdeck` 移动 App

### 9.1 页面与组件

Expo Router 下主要有连接、控制、任务和设置页面；Widget 系统支持 camera、battery、IMU、chart、map、laser scan、point cloud、diagnostics、rosout、TF tree、topic viewer 和 joystick。Layout/preset 允许针对不同机器人组合组件。

原生模块：

- `expo-gamepad`：手柄连接/按键/轴；
- `expo-compressed-video`：低开销压缩视频显示。

### 9.2 传输抽象

App 通过统一 transport 接口提供：

- connect/disconnect；
- topics/services 枚举；
- subscribe/unsubscribe；
- advertise/publish；
- callService。

实现包括 Foxglove、rosbridge 和 demo。产品默认是 Foxglove through WSS gateway；demo 只用于 UI 开发。

### 9.3 Teleop

默认发布 `/omni/cmd_vel/teleop` 的 `TwistStamped`。Publisher 是 singleton/timer 驱动，每次 publish 都重新检查：

- 当前 transport connected；
- safety ready；
- 当前 authority 是否仍属于此 App client；
- locomotion mode 是否允许；
- 输入是否仍处于 deadman/有效窗口；
- message type 是否确为 stamped。

旧 VBot `/vel_cmd` 路径仍存在于兼容配置，不应进入统一产品 profile。

### 9.4 App 控制权和安全交互

App 当前使用 legacy `/rosdeck/control_command/status`：

- App 实例生成稳定 client ID；
- acquire 后 1 Hz heartbeat；
- 约 4 s 看不到 status 会标记为不支持/失败；
- 失联后 Bridge 5 s lease 自然过期；
- 只有 status 表明 App 自己是 owner 时才发送 teleop。

Safety UI 订阅 supervisor/arbiter 状态；解除急停需要两次明确动作：arm supervisor，再 reset bridge。人工 APP takeover 可以抢占自动任务，但 UI 必须展示自动任务被中断的结果。

### 9.5 Mission UI

App 通过 Service 使用：

- DispatchMission；
- MissionControl；
- ListRoutes；
- GetCheckpointResults。

并订阅 MissionStatus、MissionEvent 和 RobotState。由于移动端 Foxglove/rosbridge 不原生承载 ROS 2 Action，DispatchMission 是 ExecuteInspection 的 fire-and-forget Service 入口，后续靠状态/事件跟踪。App 生成 idempotent request ID 和单调 sequence，重连不应随意换 key 重复派发。

### 9.6 遗留 Mapping/Navigation UI

部分组件仍发布：

- `/rosdeck/start_3d_mapping`；
- `/rosdeck/start_navigation`；
- 旧 String status。

Navigation 代码甚至可能对同名 topic 使用 Bool 和 String 两种类型。这些是旧产品路径，应迁移到 SLAM typed operation 和 Mission/Planner 服务后删除，不能与新栈并行启用。

## 10. `omni_ws_gateway`

### 10.1 连接拓扑

```text
Mobile App -- TLS 1.2+/WSS :8765 --> omni_ws_gateway
                                      |
                                      +-- loopback ws://127.0.0.1:8766 --> Foxglove Bridge
```

Gateway 不解析 ROS CDR 业务字段；它负责连接认证、角色策略、审计和上游隔离。

### 10.2 身份和防爆破

- 第一个 application message 必须是 JSON 或 CBOR login；
- token store 保存 SHA256 digest，原子写入且权限 0600；
- role：viewer、operator、admin；
- 60 秒内 5 次失败后锁定约 300 秒；
- CLI `omni-auth` 管理本地 token；
- TLS 最低版本 1.2。

### 10.3 RBAC

- viewer：订阅/读取；
- operator：允许受控 `/omni/*` 和兼容 `/rosdeck/*` topic/service；
- admin：全部 Foxglove op；
- topic/service pattern 使用显式 allowlist/wildcard；
- receive allowlist 为空时语义偏宽，生产 profile 应明确限定。

审计以 append-only JSONL 记录 login、op、topic/service、role、result 等 metadata，不记录 payload；默认按日/10MB rotation 并保留约 30 天。

### 10.4 Foxglove 二进制协议不匹配风险

这是当前容易被普通单元测试漏掉的断点：

- App 的 Foxglove transport 对 publish/service 使用 Foxglove 二进制 wire frame（opcode、channel/service ID、request ID、CDR/JSON payload）；
- Gateway 对所有 binary application message 尝试按 CBOR map 解码，并从 `{op, topic/service}` 做策略判断；
- Gateway E2E 测试发送的是自定义 CBOR map，不是 App 实际 Foxglove 二进制帧。

因此真实 App 的 publish/service binary frame 很可能被 decode error 后关闭。修复方向有两种：

1. Gateway 实现 Foxglove protocol state，跟踪 advertise/channel/service ID 并据此授权；或
2. 在认证后把标准 Foxglove frame 交给协议感知 proxy，由 proxy 完成 channel→policy 映射。

在真实 App→Gateway→Foxglove→ROS 测试通过前，不能把当前网关 E2E 当成产品协议证据。

### 10.5 TLS pin

配对流程保存服务器 SPKI pin，但在当前 TypeScript/原生网络路径中未看到完整的强制校验闭环。应以真机抓包/错误证书测试确认，而不是仅因本地存有 pin 就宣称 certificate pinning 生效。

## 11. `vbot_ros2_msgs`

仓库有 15 个纯 IDL 包、约 200 个接口，无节点、无驱动、无硬件实现。Omni 当前直接用到的只有：

- `foxglove_msgs/msg/CompressedVideo`；
- `function_msgs/srv/SetRunMode`；
- `software_msgs/srv/LowlevelAction`。

其余 camera/DVR/UWB/vision/monitor 等接口代表供应商能力目录，不代表本产品已经接线。`monitor_msgs` 中即使存在 BMS 类型，当前 Bridge 的 battery 数据仍来自其 adapter/sysfs/SDK，不应在架构图中虚构连接。

## 12. `omni_navi`：集成而非运行时

### 12.1 Manifest

核心 lock 包含：Interfaces、TF、SLAM、Planner、Bridge、Docking、Mission 和 VBot IDL。full-stack 额外加入 Inspection 和 Rosdeck。校验器要求：

- 仓库集合准确；
- GitHub SSH URL；
- 每个 version 为完整 40 字符 SHA；
- 不允许把 build/install/log checkout 进 source manifest。

### 12.2 Build profile

| Profile | 内容 | 明确排除 |
| --- | --- | --- |
| `integration` | IDL、TF、SLAM manager/interfaces、Planner、Bridge、Docking、Mission | FAST-LIO/ICP、仿真、vendor adapter |
| `full-slam` | integration + FAST-LIO/ICP | 若 Livox dependency 不存在则前置失败 |
| `vbot` | 需要的 VBot IDL + Bridge VBot adapter | 无闭源 runtime 时不能做硬件测试 |

显式 package selection 防止通用 CMake demo、Planner simulator 或旧直连 bridge 被 colcon 意外发现。

### 12.3 当前缺失

`omni_navi` 尚无：

- `omni_robot_bringup` ROS package；
- 完整 robot profile 装配；
- preflight；
- 完整 systemd target；
- 一键 startup/readiness/shutdown；
- 全栈 release artifact/BOM 生成。

现有 Bridge release/A-B 机制可以被复用，但不能把 Bridge 的 `product_bringup.launch.py` 当作整个 Omni 产品 bringup。

## 13. 北向系统必须遵守的边界

1. Cloud/Edge 不发布厂商速度 Topic，不直接调用厂商姿态/模式服务。
2. App 只发布 teleop candidate，Bridge 决定是否转发。
3. Cloud task 和 App task 都进入同一 Mission 状态机。
4. 地图 activate 只有在文件安装、hash 验证、SLAM LOCALIZED、TF ready 后才成功。
5. Evidence 由机器人本地先原子落盘，Cloud 只接收 metadata/上传，不驱动物理重采。
6. MQTT/WebSocket 重连不得重放过期运动命令。
7. Simulation adapter 必须在生产配置中显式禁用并有启动自检。
8. Video 会话失败不能影响 Bridge/Safety；媒体进程是独立故障域。
9. Web/App UI 权限不是安全边界，Backend/Gateway/Bridge 必须各自验证。
10. Cloud 失联不能阻止 Bridge 本地停车，也不能自动夺走现场 App 的有效 lease。

接口逐项接线见 [INTERFACE_MATRIX.md](INTERFACE_MATRIX.md)，机器人内部实现见 [MODULES_ROBOT_RUNTIME.md](MODULES_ROBOT_RUNTIME.md)。
