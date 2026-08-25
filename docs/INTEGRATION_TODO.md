# Omni Navi integration TODO

## P0 — blocks a coherent robot product

- [ ] Implement `/omni/control/authority` (`ControlAuthority`) in
  `omni_robot_bridge` over the existing single lease state machine.
- [ ] Migrate Mission Manager and Docking from mixed typed/string authority to
  the typed service; retain the legacy façade only for a bounded transition.
- [ ] Remove legacy pose/frame defaults (`/state_estimation_global`, `lio_map`)
  after all consumers use `omni_map -> omni_odom -> omni_base_link` and TF
  readiness.
- [ ] Merge and pin the SCAN-Planner BGY safety branch; the current candidate
  references an unmerged commit.
- [ ] Merge Rosdeck PR 24 before publishing a full-stack release lock.
- [ ] Establish cross-private-repository CI authentication with a least-
  privilege GitHub App or fine-grained machine-user token. Do not copy a broad
  developer OAuth token into Actions.
- [ ] Resolve license metadata conflicts inherited from Rosdeck before any
  external binary/source distribution.
- [ ] Fix `omni_robot_interfaces` source hygiene checks (copyright ownership,
  `LICENSE`/`CONTRIBUTING.md`, flake8 newline and pydocstyle) after the license
  decision; its contract test remains mandatory in joint CI.
- [ ] Decide and document the production source/version of
  `livox_ros_driver2`, `common_interfaces`, VBot messages and both ZsiBot SDK
  variants.

## P1 — release engineering and validation

- [ ] Add `omni_navi` x86 joint CI using the locked manifest.
- [ ] Add Orin and RDK S100 joint artifact jobs using the same release BOM.
- [ ] Introduce a product bringup package or systemd target with readiness
  gates; do not encode orchestration in App code.
- [ ] Run Matrix mapping and localization tests and archive TF trees, topic
  frames, readiness transitions and Planner command evidence.
- [ ] Validate `omni_dog.yaml` and `omni_vbot_dog.yaml` on hardware, including
  actual `header.frame_id` and complete 6DoF extrinsics.
- [ ] Add end-to-end authority tests: Mission -> Planner -> Docking -> Bridge,
  including cancel, stale command, E-stop and process death.
- [ ] Generate a signed joint release BOM containing repository SHA, CI URL,
  artifact digest, toolchain and target ABI.
- [ ] Create coordinated SemVer tags only after all required quality gates pass.

## P2 — maintainability and operations

- [ ] Generate App/cloud interface bindings or constants from the ROS contract
  source instead of manually mirroring names and numeric values.
- [ ] Standardize diagnostics, tracing IDs and time synchronization across
  Mission, Planner, Docking, Bridge and SLAM.
- [ ] Define compatibility windows and deprecation metrics for all `rosdeck_*`
  node/topic names retained from deployed systems.
- [ ] Add automatic dependency and interface-impact reporting to cross-repo PRs.
- [ ] Add Matrix nightly simulation and scheduled hardware smoke-test result
  ingestion into the GitHub Project.

## Definition of a releasable candidate

A candidate is releasable only when its manifest contains immutable SHAs, all
required quality gates are `passed` or explicitly `waived`, every artifact has
a digest, and the same BOM has been exercised on each claimed platform.
