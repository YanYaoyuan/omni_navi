# Repository catalog

Inventory date: 2026-08-25.

## Navigation core

| Repository | Visibility | Primary responsibility | Default branch | Integration note |
| --- | --- | --- | --- | --- |
| [`omni_robot_interfaces`](https://github.com/YanYaoyuan/omni_robot_interfaces) | Private fork | Stable ROS messages, services, actions and constants | `main` | Single typed contract source; README still contains pre-extraction ownership text that must be updated |
| [`omni_tf_manager`](https://github.com/YanYaoyuan/omni_tf_manager) | Public | Canonical TF authority, extrinsics, sensor aliases and readiness | `main` | SLAM implementations consume its contract; it must not depend on SLAM packages |
| [`omni_slam`](https://github.com/YanYaoyuan/omni_slam) | Private | FAST-LIO mapping, ICP relocalization and stateful SLAM manager | `main` | Full build requires Livox messages; x86/Orin/S100 platform workflows exist |
| [`SCAN-Planner`](https://github.com/YanYaoyuan/SCAN-Planner) | Public fork | Collision-aware route planning and velocity generation | `main` | Current local integration uses `feature/bgy-planner-safety-foundation`, not default `main` |
| [`omni_robot_bridge`](https://github.com/YanYaoyuan/omni_robot_bridge) | Private | Sole vendor SDK owner, authority, velocity arbitration, E-stop and RobotState | `main` | Repository renamed; ROS package remains `rosdeck_robot_bridge` for deployed-unit compatibility |
| [`omni_docking`](https://github.com/YanYaoyuan/omni_docking) | Private | Dock geometry, final servo, undock and charge verification | `main` | Currently consumes legacy string authority; typed migration is P0 |
| [`omni_mission_manager`](https://github.com/YanYaoyuan/omni_mission_manager) | Private | Mission lifecycle, route/checkpoint execution and return-to-dock orchestration | `main` | Declares typed authority client; Bridge provider is still missing |

## Product peripherals

| Repository | Visibility | Primary responsibility | Integration policy |
| --- | --- | --- | --- |
| [`rosdeck`](https://github.com/lifliu/rosdeck) | Public fork | Mobile App and authenticated App-facing WebSocket gateway | Track in full-stack BOM; never vendor robot runtime packages back into the App repo |
| [`omni-inspection`](https://github.com/YanYaoyuan/omni-inspection) | Private | Cloud backend, Web console, Edge Agent, video and deployment stack | Track API/protocol compatibility; exclude from ROS colcon builds |

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
2. Cross-repository interfaces are defined in `omni_robot_interfaces`; local
   copies of numeric constants are temporary compatibility debt.
3. Canonical frame names and extrinsics are defined in `omni_tf_manager` robot
   profiles, not duplicated in SLAM or Planner launch files.
4. `omni_navi` records integration versions and quality gates; it does not own
   the implementation source of any component above.

