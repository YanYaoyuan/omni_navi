#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "${script_dir}/.." && pwd)
workspace="${repo_root}/.workspace"
profile=integration
build_type=Release

source_ros_setup() {
  set +u
  # shellcheck disable=SC1090
  source "$1"
  set -u
}

usage() {
  echo "Usage: $0 [--workspace DIR] [--profile integration|full-slam] [--build-type TYPE]" >&2
}

while (($#)); do
  case "$1" in
    --workspace)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      workspace=$2
      shift 2
      ;;
    --profile)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      profile=$2
      shift 2
      ;;
    --build-type)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      build_type=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

case "$profile" in
  integration|full-slam) ;;
  *) echo "Unsupported profile: $profile" >&2; exit 2 ;;
esac

command -v colcon >/dev/null 2>&1 || { echo "colcon is required." >&2; exit 1; }
if [[ -z "${ROS_DISTRO:-}" ]]; then
  if [[ -f /opt/ros/humble/setup.bash ]]; then
    source_ros_setup /opt/ros/humble/setup.bash
  else
    echo "Source ROS 2 Humble before running this script." >&2
    exit 1
  fi
fi
[[ "${ROS_DISTRO:-}" == humble ]] || {
  echo "ROS_DISTRO must be humble, got: ${ROS_DISTRO:-unset}" >&2
  exit 1
}

src="${workspace}/src"
required_repositories=(
  SCAN-Planner omni_docking omni_mission_manager omni_robot_bridge
  omni_robot_interfaces omni_slam omni_tf_manager
)
for repository in "${required_repositories[@]}"; do
  [[ -d "${src}/${repository}" ]] || {
    echo "Missing ${src}/${repository}; run scripts/import_workspace.sh first." >&2
    exit 1
  }
done

base_paths=(
  "${src}/omni_robot_interfaces"
  "${src}/omni_tf_manager"
  "${src}/omni_slam/omni_slam_interfaces"
  "${src}/omni_slam/omni_slam_manager"
  "${src}/SCAN-Planner/src/planner"
  "${src}/omni_robot_bridge"
  "${src}/omni_docking"
  "${src}/omni_mission_manager"
)
targets=(
  omni_tf_manager omni_slam_manager scan_planner omni_docking
  omni_mission_manager
)

if [[ "$profile" == full-slam ]]; then
  if ! ros2 pkg prefix livox_ros_driver2 >/dev/null 2>&1; then
    echo "full-slam requires livox_ros_driver2 in the sourced environment." >&2
    exit 1
  fi
  base_paths+=(
    "${src}/omni_slam/FAST_LIO"
    "${src}/omni_slam/icp_relocalization"
  )
  targets+=(fast_lio icp_relocalization)
fi

mkdir -p -- "$workspace"
cd -- "$workspace"
echo "[omni_navi] x86 build profile=$profile build_type=$build_type"
colcon build \
  --base-paths "${base_paths[@]}" \
  --packages-up-to "${targets[@]}" \
  --cmake-args "-DCMAKE_BUILD_TYPE=${build_type}" \
  --event-handlers console_cohesion+

colcon build \
  --base-paths "${base_paths[@]}" \
  --packages-select rosdeck_robot_bridge \
  --cmake-args \
    "-DCMAKE_BUILD_TYPE=${build_type}" \
    -DROSDECK_BUILD_VBOT_ADAPTER=OFF \
    -DROSDECK_BUILD_ZSIBOT_ADAPTER=OFF \
  --event-handlers console_cohesion+
