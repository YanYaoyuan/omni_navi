# Repository catalog

Inventory date: 2026-08-26.

## Navigation core

| Repository | Visibility | Primary responsibility | Default branch | Integration note |
| --- | --- | --- | --- | --- |
| [`omni_robot_interfaces`](https://github.com/YanYaoyuan/omni_robot_interfaces) | Private fork | Stable ROS messages, services, actions and constants | `main` | Single typed contract source; README still contains pre-extraction ownership text that must be updated |
| [`omni_tf_manager`](https://github.com/YanYaoyuan/omni_tf_manager) | Public | Canonical TF authority, extrinsics, sensor aliases and readiness | `main` | V1 temporarily owns SlamStatus; V2 moves that type to interfaces with SLAM as producer and TF/Bridge/Mission as consumers |
| [`omni_slam`](https://github.com/YanYaoyuan/omni_slam) | Private | FAST-LIO mapping, ICP relocalization and stateful SLAM manager | `main` | Full build requires Livox messages; x86/Orin/S100 platform workflows exist |
| [`SCAN-Planner`](https://github.com/YanYaoyuan/SCAN-Planner) | Public fork | Collision-aware route planning and velocity generation | `main` | Current local integration uses `feature/bgy-planner-safety-foundation`, not default `main` |
| [`omni_robot_bridge`](https://github.com/YanYaoyuan/omni_robot_bridge) | Private | Sole vendor SDK owner, authority, velocity arbitration, E-stop and RobotState | `main` | Repository renamed; ROS package remains `rosdeck_robot_bridge` for deployed-unit compatibility |
| [`omni_docking`](https://github.com/YanYaoyuan/omni_docking) | Private | Dock geometry, final servo, undock and charge verification | `main` | Python is a behavior prototype; production target is a same-repository, single-process C++ rewrite with relative-pose/contact gates |
| [`omni_mission_manager`](https://github.com/YanYaoyuan/omni_mission_manager) | Private | Mission lifecycle, route/checkpoint execution and return-to-dock orchestration | `main` | Python is a behavior prototype; production target is a same-repository, single-process C++ rewrite after contract freeze |

## Product peripherals

| Repository | Visibility | Primary responsibility | Integration policy |
| --- | --- | --- | --- |
| [`rosdeck`](https://github.com/lifliu/rosdeck) | Public upstream/shared repo | Mobile App and authenticated App-facing WebSocket gateway | Gateway is the only App-facing runtime adapter exception; do not place Mission/Docking/Bridge/vendor control back into the App repo |
| [`omni-inspection`](https://github.com/YanYaoyuan/omni-inspection) | Private | C++ Edge/载荷、Go backend/video、TS Web console and deployment | Edge becomes a typed ROS facade; add one C++ `omni_inspection_executor` package here without creating a new repository |

最小新增口径固定为：两个 package、一个新运行进程、零个新仓库。`omni_navi` 增加无业务节点的 `omni_robot_bringup`；现有 `omni-inspection` 增加唯一新进程 `omni_inspection_executor`。

## Not independent product repositories

- `build/`, `install/`, `log/`, `.ruff_cache/` and `.pytest_cache/` are local
  outputs and must never enter a source manifest.
- `SCAN-Planner/zsibot_sdk` contains vendor/platform material inside the Planner
  checkout. It is not a source of product command authority; unified robot
  control belongs to `omni_robot_bridge`.
- Simulator packages under `SCAN-Planner/src/simulator` are validation tools,
  not production navigation packages.

## Source-of-truth rules

1. A ROS package has one owning repository.
2. Cross-repository product interfaces are defined in `omni_robot_interfaces`.
   V1 `omni_tf_manager/SlamStatus` and `omni_slam_interfaces` are explicit
   migration exceptions; V2 removes those ownership leaks. Local copies of
   numeric constants are temporary compatibility debt.
3. Canonical frame names and extrinsics are defined in `omni_tf_manager` robot
   profiles, not duplicated in SLAM or Planner launch files.
4. `omni_navi` records integration versions and quality gates; it does not own
   the implementation source of any component above.
5. `omni_navi` may own the configuration-only `omni_robot_bringup` package,
   systemd target, preflight and product BOM. It must not duplicate component
   business state machines.
6. Edge/App/Cloud code may translate authenticated requests into typed product
   interfaces, but must never publish vendor/final velocity or implement a
   second patrol/navigation state machine.
