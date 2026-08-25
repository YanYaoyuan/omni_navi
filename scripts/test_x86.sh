#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "${script_dir}/.." && pwd)
workspace="${repo_root}/.workspace"

source_ros_setup() {
  set +u
  # shellcheck disable=SC1090
  source "$1"
  set -u
}

if [[ ${1:-} == --workspace && $# -eq 2 ]]; then
  workspace=$2
elif (($#)); then
  echo "Usage: $0 [--workspace DIR]" >&2
  exit 2
fi

command -v colcon >/dev/null 2>&1 || { echo "colcon is required." >&2; exit 1; }
[[ -f "${workspace}/install/setup.bash" ]] || {
  echo "Build output not found: ${workspace}/install/setup.bash" >&2
  exit 1
}

if [[ -f /opt/ros/humble/setup.bash ]]; then
  source_ros_setup /opt/ros/humble/setup.bash
fi
source_ros_setup "${workspace}/install/setup.bash"

cd -- "$workspace"
export ROS_LOG_DIR="${workspace}/log/ros"
mkdir -p -- "$ROS_LOG_DIR"

# omni_robot_interfaces is built above and its generated contract is exercised
# here. Its ament copyright linter remains owned by that source repository until
# the inherited license metadata is resolved; do not invent a product license in
# this integration repository.
python3 src/omni_robot_interfaces/ci/check_contract_constants.py

colcon test \
  --packages-select \
    plan_env omni_tf_manager omni_slam_interfaces scan_planner_msgs \
    path_searching bspline_opt traj_utils scan_planner omni_slam_manager \
    rosdeck_robot_bridge \
  --event-handlers console_cohesion+
colcon test-result --verbose

# The extracted Python packages currently expose their suites through unittest
# rather than ament/colcon, so run them explicitly as part of the joint gate.
python3 -m unittest discover -s src/omni_docking/test -v
python3 -m unittest discover -s src/omni_mission_manager/test -v
