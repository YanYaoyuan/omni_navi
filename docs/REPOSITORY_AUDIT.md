# Omni 全仓库源码审计清单

> 审计日期：2026-08-28
>
> 审计对象：`/Users/yan/WorkSpace/Omni/robot` 下 11 个独立 Git 仓库
>
> 用途：说明本文档集到底阅读了什么、当前工作区与发布锁定版本有何差异，以及每个源码包是否进入产品运行时。

## 1. 如何阅读本清单

本清单区分两套容易混淆的基线：

- **源码审计快照**：2026-08-28 当前工作区实际检出的提交。本文档对模块行为的描述以它为准。
- **集成锁定基线**：`omni_navi/manifests/*.lock.repos` 固定的不可变提交。它用于可复现导入和候选发布，不会自动跟随本地仓库。

状态术语：

- **产品路径**：按现有配置会进入机器人、App 或 Cloud 的正式运行路径。
- **可选路径**：需要编译开关、启动参数或部署 profile 才会运行。
- **开发工具**：测试、仿真、可视化、录线或验证工具，不应进入产品控制面。
- **遗留路径**：仍保留兼容性，但新模块不应再依赖。
- **缺口**：接口、配置或设计已经存在，实际 provider、接线或验证尚不存在。

## 2. 仓库与版本基线

| 仓库 | 2026-08-28 审计提交 | 锁定清单提交 | 是否一致 | 审计范围 |
| --- | --- | --- | --- | --- |
| `omni_navi` | `3a3628dd8cef4c5758af355951b40709cf1d3e20` | 不适用，自身即清单所有者 | — | manifest、构建/测试脚本、架构、交付计划 |
| `omni_robot_interfaces` | `f0dbd6c40fc21def30d1350a7df378b973779ff1` | 同左 | 是 | 全部 5 msg、10 srv、5 action、契约常量检查 |
| `omni_tf_manager` | `cc6bd998b6942b55ba7ea37b0bbfbbbd3c628306` | `790f0d4f2696ad4a957a32b61742378bb146baa3` | 否 | 节点、坐标变换数学、profile、alias、ready、测试 |
| `omni_slam` | `2388ed78468fd632cc1c1b842c0f77993c6b0197` | `dbdf26774199cf93d7cf7c7da94eabf039b850c9` | 否 | FAST-LIO、ICP、接口、管理器、地图存储、跨平台部署 |
| `omni_planner` | `26d021c6112c858f43bd60ef31bb9940d289670f` | `68cacc5e5e68ea6f61d96ae925a6fe41edb6279e` | 否 | 六个规划包、控制器、FollowRoute、仿真、遗留桥接 |
| `omni_robot_bridge` | `14f27ca480c605c8e7f559a75f68de7d598ce60f` | 同左 | 是 | Bridge、Safety、VBot/ZsiBot adapter、部署与 A/B 更新 |
| `omni_docking` | `67c0d8268d513e8d380c3a54467c29441262802e` | 同左 | 是 | Dock/Undock、租约、末端控制、充电判断、配置与测试 |
| `omni_mission_manager` | `5293de5cfb31a634b5b0daf7e70b9bfc7e30ccf4` | 同左 | 是 | 任务状态机、分段、检查点、SQLite、返航链、ROS 接线 |
| `omni-inspection` | `dbfc9518f1a61688eaf1d2510271c584e3226c3c` | full-stack 清单同左 | 是 | Edge、Go 后端、Web、视频、协议、数据库、Compose |
| `rosdeck` | `e7794d1e2836442849642b040e0a15b594233421` | `69b8efdb1e50ebeb51ee602b7c11b686b80410ca` | 否 | Expo App、传输层、控制/任务 UI、WSS 网关、原生模块 |
| `vbot_ros2_msgs` | `a598337a7c4ec6a13cfe28ec6a8adf6866278a3c` | 同左 | 是 | 15 个纯 IDL 包及当前真实引用 |

审计开始时 11 个仓库均为干净工作区。本次只修改 `omni_navi/docs`；表中提交用于说明阅读输入，不代表本文档修改后的新提交。

### 2.1 版本差异的影响

Planner、SLAM、TF Manager 和 Rosdeck 的本文行为描述包含了锁定提交之后的本地实现。发布前必须二选一：

1. 将验证过的当前提交更新进 lock manifest，并生成新的联合 BOM；或
2. 重新以 lock manifest 导入隔离工作区，再对锁定代码重复契约和整机测试。

不能拿当前工作区测试结果为旧锁定提交背书。

## 3. 39 个 ROS 2 包清单

### 3.1 产品接口和机器人运行时

| 包 | 仓库 | 类型 | 入口/职责 | 产品地位 |
| --- | --- | --- | --- | --- |
| `omni_robot_interfaces` | `omni_robot_interfaces` | `ament_cmake` IDL | 跨仓 msg/srv/action | 产品路径，合同源 |
| `omni_tf_manager` | `omni_tf_manager` | C++ | `omni_tf_manager_node` | 产品路径 |
| `fast_lio` | `omni_slam` | C++ | `fastlio_mapping` | full-slam 产品路径 |
| `icp_relocalization` | `omni_slam` | C++ | `icp_node`、`global_pointcloud_publisher`、`sac_ia_gicp` | 前两者产品；SAC-IA/GICP 可选研究路径 |
| `omni_slam_interfaces` | `omni_slam` | IDL | 建图/定位操作和状态所需接口 | V1 产品路径，V2 应迁移 |
| `omni_slam_manager` | `omni_slam` | Python | `omni_slam_manager`、`omni_slam_ctl` | 产品控制面 |
| `plan_env` | `omni_planner` | C++ library | 概率栅格、raycast、膨胀、碰撞查询 | 产品路径 |
| `path_searching` | `omni_planner` | C++ library | projected A* / kinodynamic 搜索 | 产品路径 |
| `bspline_opt` | `omni_planner` | C++ library | B-spline 优化和约束代价 | 产品路径 |
| `traj_utils` | `omni_planner` | C++ library/IDL | 轨迹表达、可视化辅助 | 产品路径 |
| `scan_planner_msgs` | `omni_planner` | IDL | B-spline、规划心跳等内部消息 | 产品内部接口 |
| `scan_planner` | `omni_planner` | C++ | planner、FollowRoute、closed-loop controller、route publisher | 产品路径 |
| `rosdeck_robot_bridge` | `omni_robot_bridge` | C++ | `rosdeck_robot_bridge_node`、`rosdeck_safety_supervisor_node` | 产品安全边界；包名为兼容旧部署保留 |
| `omni_docking` | `omni_docking` | Python | `docking_node` | 当前行为原型/候选产品路径 |
| `omni_mission_manager` | `omni_mission_manager` | Python | `mission_manager_node` | 当前行为原型/候选产品路径 |
| `omni_ws_gateway` | `rosdeck/robot` | Python | `omni-ws-gateway`、`omni-auth` | App 面产品边界 |

### 3.2 Planner 仿真与遗留包

| 包 | 职责 | 分类 |
| --- | --- | --- |
| `go2_description` | Go2 URDF/描述资源 | 仿真/可视化 |
| `odom_visualization` | 里程计和路径可视化 | 开发工具 |
| `pose_utils` | 位姿工具 | 仿真工具 |
| `waypoint_generator` | RViz/交互式目标和航点生成 | 开发工具 |
| `local_sensing_node` | 仿真局部感知 | 仿真 |
| `map_generator` | 仿真地图生成 | 仿真 |
| `mockamap` | 程序化点云地图 | 仿真 |
| `zsibot_cmd_bridge` | Planner 到 ZsiBot 的旧直连命令桥 | 遗留路径；正式产品必须关闭 |

S100 产品构建脚本使用白名单排除这些仿真包和 `zsibot_cmd_bridge`。`scan_planner` 内仍保留的开环控制器、UDP client、运动学模拟器也由显式编译/launch 开关控制。

### 3.3 `vbot_ros2_msgs` 上游接口包

| 包 | 上游领域 | 当前 Omni 直接使用 |
| --- | --- | --- |
| `camera_msgs` | 相机控制/状态 | 否 |
| `dvr_msgs` | DVR | 否 |
| `firmware_version_msgs` | 固件版本 | 否 |
| `foxglove_msgs` | Foxglove 视频消息 | `CompressedVideo` 被视频流使用 |
| `function_msgs` | 机器人功能服务 | Bridge/Edge 使用 `SetRunMode` |
| `lowlevel_msg` | 低层控制消息 | 否 |
| `monitor_msgs` | 监控和 BMS 类消息 | 当前 Bridge 未直接接线 |
| `peripheral_msgs` | 外设 | 否 |
| `slam_msgs` | 厂商 SLAM | 否 |
| `software_msgs` | 软件控制服务 | Bridge/Edge 使用 `LowlevelAction` |
| `speech_msgs` | 语音 | 否 |
| `topic_header_msgs` | 厂商公共头 | 间接依赖 |
| `uwb_location` | UWB 定位 | 否 |
| `uwb_msgs` | UWB 消息 | 否 |
| `vision_msgs` | 厂商视觉 | 否 |

这些包是供应商合同目录，不等于 15 组产品功能都已经接入。正式构建只选择真实需要的 `foxglove_msgs`、`function_msgs`、`software_msgs`，其余不应被误写成当前能力。

## 4. 非 ROS 子系统清单

### 4.1 `omni-inspection`

| 目录 | 技术栈 | 入口 | 职责 |
| --- | --- | --- | --- |
| `backend/cmd/server` | Go | `main.go` | REST、WebSocket、MQTT、业务服务、调度器装配 |
| `backend/internal/api` | Go/Gin | router/handlers | JWT/RBAC API、限流、健康检查、指标 |
| `backend/internal/service` | Go | 多领域 service | 机器人、控制、地图、导航、巡检、告警、录像、OTA、维护等业务 |
| `backend/internal/store` | Go/PostgreSQL/Redis | store | 持久化模型、查询、实时缓存与内存降级 |
| `backend/internal/mqtt` | Go | MQTT client | 设备上行消费、命令下发、ACK/离线队列 |
| `backend/migrations` | SQL | migration files | 数据库 schema 演进 |
| `edge-agent` | C++17 | `src/main.cpp` | MQTT 设备代理、遥测、命令验证、机器人/导航/video adapter |
| `edge-agent/video_streamer` | C++/GStreamer | dog video streamer | ROS 图像到 RTP/SRT，硬件转码可选 |
| `video-gateway` | Python/ffmpeg | `server.py` | RTSP→MJPEG、快照、录像 |
| `video-webrtc-gateway` | Go/Pion | `main.go` | 可选 WebRTC gateway |
| `video-transcoder` | ffmpeg container | Dockerfile | 可选转码 |
| `web-console` | Vue/TypeScript | `src/main.ts` | 管理控制台 |
| `protocols` | JSON Schema/Markdown | MQTT/schema | Cloud↔Edge 合同 |
| `deploy` | Compose/nginx/MediaMTX | compose/config | 云端与视频部署、观测组件 |

### 4.2 `rosdeck`

| 目录 | 技术栈 | 职责 |
| --- | --- | --- |
| `app`, `components`, `widgets` | React Native / Expo | 连接、控制、任务、设置页面和可配置 ROS 可视化组件 |
| `lib` | TypeScript | Foxglove/rosbridge/demo 传输、消息编码、控制和任务辅助 |
| `stores`, `hooks` | TypeScript | 连接、机器人、任务和 UI 状态 |
| `modules/expo-gamepad` | Native module | 手柄输入 |
| `modules/expo-compressed-video` | Native module | 压缩视频解码/显示 |
| `robot/omni_ws_gateway` | Python | TLS、登录、RBAC、审计、Foxglove 上游代理 |
| `sdk/vbot_ros2_msgs` | App 侧类型资源 | 厂商接口展示/兼容资源，不是 ROS 源包 |

## 5. `omni_navi` 本身的职责

`omni_navi` 当前没有 ROS `package.xml` 和业务节点，属于纯集成仓库：

- `manifests/omni_navi.lock.repos`：8 个导航/机器人核心 checkout；
- `manifests/omni_full_stack.lock.repos`：在核心之上加入 `omni-inspection` 和 `rosdeck`；
- `scripts/import_workspace.sh`：安全导入，不删除/重置已有 checkout；
- `scripts/build_x86.sh`：`integration`、`full-slam`、`vbot` 三种显式包选择；
- `scripts/test_x86.sh`：联合测试入口；
- `scripts/validate_manifests.py`：仓库集合、SSH URL、40 字符 SHA 和 release metadata 的合同检查；
- `docs`：仓库职责、架构、构建和集成交付事实源。

计划中的 `omni_robot_bringup` 尚未存在；因此当前不能从 `omni_navi` 一键拉起完整机器人栈。

## 6. 阅读与验证证据

本次逐项检查了：

- 运行入口、launch、systemd、容器 Compose 和交叉编译脚本；
- ROS IDL、Topic/Service/Action 名称、QoS、timer 和 watchdog；
- 状态机、幂等键、持久化格式、地图/路线/Dock 数据结构；
- 运动控制权、急停、速度限幅、最终输出和厂商 SDK ownership；
- Cloud MQTT、REST、WebSocket、视频和 App 传输边界；
- 所有可见测试目录和关键回归测试。

在本机不安装新依赖的前提下执行的测试结果：

| 模块 | 结果 | 解释 |
| --- | --- | --- |
| Docking 行为内核 | 108/108 通过 | 几何、速度、租约文本协议、BMS 判定、状态机 |
| Mission 行为内核 | 208/208 通过 | 路线、检查点、SQLite 状态机、返航逻辑 |
| Bridge Python 合同/发布测试 | 44 通过、1 跳过 | C++ gtest 未在非 ROS macOS 环境编译执行 |
| Planner 静态合同测试 | 14 通过；2 个 ROS launch test 未导入 | 当前环境没有 ROS 2 `launch` Python 包 |
| FAST-LIO Python 回归 | 20/20 通过 | 静态/源码级回归，不是传感器运行测试 |
| TF profile 测试 | 未执行 | 当前 Python 缺少 PyYAML |
| WSS Gateway 非网络测试 | 69/69 通过 | token、审计、CBOR、策略、WebSocket frame |
| WSS Gateway E2E | 9 项因沙箱禁用 loopback bind 未执行 | 是环境限制，不计为代码失败，也不计通过 |
| SLAM Manager | 42 通过、4 项 ROS 环境跳过、1 项因缺少 PyYAML 导入失败 | 未形成完整通过证据 |
| Rosdeck App | 未执行 | `jest` 依赖未安装 |
| Go backend/Web console/C++ ROS | 未做全量构建 | 需要相应依赖、ROS 2 Humble 或容器环境 |
| Navi manifest/release metadata | 两份 manifest 与一份 release schema 独立验证通过 | 官方 Python validator 因本机缺 PyYAML 未直接运行 |

这些结果只证明可执行的局部逻辑。真实放行仍需 ROS 图级测试、Matrix 仿真、目标板 smoke/HIL 和真机安全测试。

## 7. 覆盖结论

本次文档覆盖 11 个仓库、39 个 ROS 源包、4 类非 ROS 产品端（Edge、Cloud、Web、移动 App）、三条视频实现路径及全部 manifest/build/release 入口。`build/`、`install/`、`log/`、`.pytest_cache/`、`dist/omni_slam` 等生成物只用于辨别边界，没有作为源码模块重复分析。

模块行为详见：

- [机器人运行时模块](MODULES_ROBOT_RUNTIME.md)
- [平台、边缘、视频与客户端](MODULES_PLATFORM_CLIENTS.md)
- [跨模块接口矩阵](INTERFACE_MATRIX.md)
- [整机架构](ARCHITECTURE.md)
