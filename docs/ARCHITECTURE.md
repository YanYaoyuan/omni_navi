# Omni Navi system architecture

## Dependency direction

```text
omni_robot_interfaces
  ├── omni_tf_manager
  ├── SCAN-Planner
  ├── omni_robot_bridge
  ├── omni_docking
  └── omni_mission_manager

omni_tf_manager
  ├── omni_slam manager integration
  └── omni_robot_bridge SlamStatus / readiness integration

omni_slam
  └── pose + mapping/localization status

SCAN-Planner
  └── navigation velocity candidate

omni_robot_bridge
  ├── authoritative RobotState
  └── sole final velocity / vendor SDK owner

omni_mission_manager
  ├── FollowRoute -> SCAN-Planner
  └── Dock -> omni_docking
```

High-level modules depend on stable interfaces and readiness state. Interface,
TF and vendor abstractions must never depend on mission policy or App code.

## Runtime command path

```text
App / cloud
    |
    | ExecuteInspection / MissionControl / ReturnToDock
    v
omni_mission_manager
    |                         +---------------------------+
    | FollowRoute             | Dock / Undock             |
    v                         v                           |
SCAN-Planner             omni_docking                    |
    |                         |                           |
    | /scan_planner/cmd_vel   | /omni/cmd_vel/docking     |
    +-------------------------+---------------------------+
                              v
                       omni_robot_bridge
                              |
                              | one authorized, clamped,
                              | watchdog-protected command
                              v
                         Vendor SDK
```

Teleoperation has a separate `/omni/cmd_vel/teleop` input. No producer may
publish directly to the vendor-facing path or bypass Bridge authority.

## Localization and TF path

The canonical tree is:

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

`omni_slam` estimates pose and publishes SLAM mode/status. `omni_tf_manager`
owns canonical frame names, static extrinsics, dynamic TF normalization and
`/omni/tf_manager/ready`. Planner, Mission and Docking consume this normalized
contract instead of robot-specific sensor frame names.

## Startup/readiness order

1. `omni_tf_manager` loads a robot profile and validates its 6DoF extrinsics.
2. `omni_slam_manager` starts; mapping/localization may still be stopped.
3. `omni_robot_bridge` acquires the sole SDK-owner lock and starts fail-closed.
4. SLAM enters mapping or localization and publishes fresh status/pose.
5. Planner becomes ready only after TF, odometry and cloud gates pass.
6. Docking and Mission nodes may be alive earlier but reject goals until
   `RobotState`, TF and localization are fresh.
7. App and cloud expose authenticated operations after robot readiness is
   observable.

Process liveness is never equivalent to motion readiness.

## Release boundaries

- Contract or constant changes begin in `omni_robot_interfaces` and require a
  coordinated consumer matrix.
- Frame or extrinsic changes begin in `omni_tf_manager` and require Matrix plus
  real-robot validation.
- Planner, SLAM and vendor adapters may produce platform-specific artifacts,
  but a product release pins identical source SHAs across x86, Orin and S100.
- App and cloud are tracked in the full-stack manifest, not the ROS core build.

