# omni_navi

Omni 巡检机器人的导航产品集成仓库。这里不复制各模块源码，而是统一管理：

- 可复现的多仓库版本锁定；
- x86 联合导入、构建和测试入口；
- 模块职责、接口和启动顺序；
- x86、Orin、RDK S100 的联合发布计划；
- 跨仓库集成问题和发布 BOM。

## 产品边界

```text
Local App --> omni_ws_gateway --+
                                |
Cloud -----> Edge Agent --------+--> omni_mission_manager
                                      |       |       |
                                      v       v       v
                                  Planner  Docking  Inspection Executor
                                      |       |
                                      +---+---+
                                          v
                                  omni_robot_bridge ---> Vendor SDK
                                          ^
                                SLAM --> TF/RobotState

V2 product contracts: omni_robot_interfaces
V1 migration exceptions: omni_tf_manager/SlamStatus, omni_slam_interfaces
```

## 仓库分层

| 分层 | 仓库 |
| --- | --- |
| 接口与坐标系 | `omni_robot_interfaces`, `omni_tf_manager` |
| 定位与规划 | `omni_slam`, `omni_planner` |
| 机器人运行时 | `omni_robot_bridge`, `omni_docking`, `omni_mission_manager` |
| 机器人边缘与载荷 | `omni-inspection/edge-agent`, `omni_inspection_executor` |
| App 与云平台 | `rosdeck`, `omni-inspection/backend`, `web-console`, `video-webrtc-gateway` |

详细职责和远端地址见 [docs/REPOSITORIES.md](docs/REPOSITORIES.md)，系统关系见
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

2026-08-28 全仓源码审计将详细内容拆成四个配套索引：

- [机器人运行时模块详解](docs/MODULES_ROBOT_RUNTIME.md)；
- [平台、边缘、视频与客户端模块详解](docs/MODULES_PLATFORM_CLIENTS.md)；
- [跨模块接口矩阵](docs/INTERFACE_MATRIX.md)；
- [仓库、包、版本与测试证据清单](docs/REPOSITORY_AUDIT.md)。

2026-08-30 在上述事实审计上新增
[逐模块缺失与补齐分析](docs/MODULE_GAP_ANALYSIS.md)，逐项区分算法、运行时、
集成、产品和验证缺口，并给出 SLAM 后端、Mission/Docking C++、Inspection
Executor、Bridge authority/readiness、Edge/App 收敛以及整机放行标准。

总架构文档明确区分当前实现、目标路径、遗留兼容和放行缺口；单个
Topic、接口或单元测试存在，不代表整机巡检链已经接通。

当前三人团队的近期交付顺序见
[docs/INTEGRATION_TODO.md](docs/INTEGRATION_TODO.md)。Mission Manager 与 Docking
的 C++ 行为重写分别在 `omni_mission_manager/docs/CPP_REWRITE_DESIGN.md` 和
`omni_docking/docs/CPP_REWRITE_DESIGN.md` 中定义；这两份文件应先在各自仓库提交，
再恢复为对应远端 main 的可点击链接。

整机最小新增仅包含两个 package、一个新运行进程、零个新仓库：
`omni_robot_bringup` 是无业务节点的集成包，`omni_inspection_executor` 是位于
现有 `omni-inspection` 仓库的唯一新增机器人运行进程。

## 获取固定版本

安装 `vcstool` 后，在本仓库执行：

```bash
./scripts/import_workspace.sh
```

默认导入 [manifests/omni_navi.lock.repos](manifests/omni_navi.lock.repos)
中固定的 7 个导航核心仓库和 VITA 官方 `vbot_ros2_msgs` 接口仓库，目标目录为
`.workspace/src`。清单使用 commit SHA，
相同清单在不同机器上得到相同源码。

若需要同时拉取 App 和云平台：

```bash
./scripts/import_workspace.sh \
  --manifest manifests/omni_full_stack.lock.repos \
  --workspace .full-stack
```

## x86 联合构建

```bash
source /opt/ros/humble/setup.bash
./scripts/build_x86.sh --workspace .workspace
./scripts/test_x86.sh --workspace .workspace
```

默认 profile 构建跨仓库接口、TF、SLAM 管理器、Planner、Bridge、Docking 和
Mission Manager，但不构建 FAST-LIO/ICP 算法包、仿真包或厂商适配器。完整 SLAM
profile 要求先提供 `livox_ros_driver2` 和对应平台依赖：

```bash
./scripts/build_x86.sh --workspace .workspace --profile full-slam
```

构建 VBot ROS 接口和 Bridge 的 VBot adapter：

```bash
./scripts/build_x86.sh --workspace .workspace --profile vbot
```

`vbot_ros2_msgs` 保持为独立上游仓库，仅通过 manifest 固定版本，不在本仓库复制
源码。闭源 VBot 运行时由目标机器人提供，不属于该接口仓库。

具体依赖与失败条件见 [docs/BUILD.md](docs/BUILD.md)。

## 发布原则

1. 每个功能仓库独立评审和 CI；本仓库只集成已合并 commit。
2. 联合版本使用不可变 SHA，不使用浮动 `main` 作为发布输入。
3. x86、Orin、S100 通过同一 BOM 追踪源码，平台产物可不同。
4. TF、接口、控制权和安全契约的破坏性变化必须联合发布。
5. App/Cloud 服务可以独立发布，但接口版本必须记录在全栈 BOM；机器人侧 Edge Agent 和 Inspection Executor 必须进入机器人 BOM、联合 CI 与目标机部署验证。

当前集成缺口和优先级见 [docs/INTEGRATION_TODO.md](docs/INTEGRATION_TODO.md)。
