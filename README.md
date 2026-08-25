# omni_navi

Omni 巡检机器人的导航产品集成仓库。这里不复制各模块源码，而是统一管理：

- 可复现的多仓库版本锁定；
- x86 联合导入、构建和测试入口；
- 模块职责、接口和启动顺序；
- x86、Orin、RDK S100 的联合发布计划；
- 跨仓库集成问题和发布 BOM。

## 产品边界

```text
Rosdeck App / Cloud
        |
        v
omni_mission_manager ------> SCAN-Planner
        |                         |
        v                         v
  omni_docking ----------> omni_robot_bridge ---> Vendor SDK
        ^                         ^
        |                         | RobotState / SlamStatus
        +-------------------------+---- omni_slam
                                      omni_tf_manager

All typed contracts: omni_robot_interfaces
```

## 仓库分层

| 分层 | 仓库 |
| --- | --- |
| 接口与坐标系 | `omni_robot_interfaces`, `omni_tf_manager` |
| 定位与规划 | `omni_slam`, `SCAN-Planner` |
| 机器人运行时 | `omni_robot_bridge`, `omni_docking`, `omni_mission_manager` |
| App 与云平台 | `rosdeck`, `omni-inspection` |

详细职责和远端地址见 [docs/REPOSITORIES.md](docs/REPOSITORIES.md)，系统关系见
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 获取固定版本

安装 `vcstool` 后，在本仓库执行：

```bash
./scripts/import_workspace.sh
```

默认导入 [manifests/omni_navi.lock.repos](manifests/omni_navi.lock.repos)
中固定的 7 个导航核心仓库，目标目录为 `.workspace/src`。清单使用 commit SHA，
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

具体依赖与失败条件见 [docs/BUILD.md](docs/BUILD.md)。

## 发布原则

1. 每个功能仓库独立评审和 CI；本仓库只集成已合并 commit。
2. 联合版本使用不可变 SHA，不使用浮动 `main` 作为发布输入。
3. x86、Orin、S100 通过同一 BOM 追踪源码，平台产物可不同。
4. TF、接口、控制权和安全契约的破坏性变化必须联合发布。
5. App/云平台可以独立发布，但其接口版本必须记录在全栈 BOM 中。

当前集成缺口和优先级见 [docs/INTEGRATION_TODO.md](docs/INTEGRATION_TODO.md)。

