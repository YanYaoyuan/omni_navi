# Joint build guide

## Supported integration baseline

- Ubuntu 22.04
- ROS 2 Humble
- C++17
- Python 3.10
- `colcon`, `vcstool`, `rosdep`
- Eigen, PCL and the ROS dependencies declared by each package

The first integration target is x86_64. Orin and RDK S100 reuse the same source
lock but keep platform-specific toolchains and artifact packaging in the
component repositories until the joint pipeline is proven.

## Import

```bash
sudo apt-get install python3-vcstool python3-colcon-common-extensions python3-rosdep
./scripts/import_workspace.sh
```

The repositories are imported under `.workspace/src`. Existing checkouts are
not deleted or reset by the script.

## Dependency installation

Review `rosdep` output before installing on a production host:

```bash
source /opt/ros/humble/setup.bash
rosdep install \
  --from-paths .workspace/src \
  --ignore-src --rosdistro humble -r -y
```

Known non-generic dependencies:

| Component/profile | External input |
| --- | --- |
| FAST-LIO/ICP | `livox_ros_driver2`, `common_interfaces`, PCL/Eigen |
| VBot adapter | `function_msgs`, `software_msgs`, matching VBot runtime |
| ZsiBot adapter | Correct ZSL-1 or ZSL-1W vendor SDK and ABI |
| Orin | Target-compatible sysroot/toolchain and vendor libraries |
| RDK S100 | `/opt/tros/humble` or compatible sysroot/toolchain |

The integration profile disables VBot and ZsiBot adapters. It intentionally
does not fabricate vendor dependencies.

## Build profiles

Integration surface:

```bash
./scripts/build_x86.sh --profile integration
```

This selects explicit package roots so generic CMake demos and Planner
simulator packages are not accidentally discovered.

Full SLAM algorithms:

```bash
source /path/to/livox_workspace/install/setup.bash
./scripts/build_x86.sh --profile full-slam
```

The script fails before colcon if `livox_ros_driver2` is unavailable.

## Tests

```bash
./scripts/test_x86.sh
```

The command runs the interface contract check, TF manager, Planner, SLAM
manager, Bridge, Docking and Mission tests. A writable workspace-local
`ROS_LOG_DIR` is used so launch tests also work in containers and restricted CI
runners. The command fails on any `colcon test-result` or standalone Python
suite error.

`omni_robot_interfaces` is compiled and its contract constants are checked, but
its package-level ament copyright test is intentionally not duplicated here.
That repository currently has inherited license metadata which must be resolved
at the source before a product license can be asserted. The exception is tracked
as a release blocker and is not a waiver.

Matrix mapping/localization, vendor SDK and hardware tests remain separate
release quality gates because they require running systems, sensors or target
hardware.
