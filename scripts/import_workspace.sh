#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "${script_dir}/.." && pwd)
manifest="${repo_root}/manifests/omni_navi.lock.repos"
workspace="${repo_root}/.workspace"

usage() {
  echo "Usage: $0 [--manifest FILE] [--workspace DIR]" >&2
}

while (($#)); do
  case "$1" in
    --manifest)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      manifest=$2
      shift 2
      ;;
    --workspace)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      workspace=$2
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

command -v vcs >/dev/null 2>&1 || {
  echo "vcs is required. Install python3-vcstool or vcstool first." >&2
  exit 1
}
[[ -f "$manifest" ]] || { echo "Manifest not found: $manifest" >&2; exit 1; }

mkdir -p -- "$workspace/src"
echo "[omni_navi] importing $manifest into $workspace/src"
vcs import --recursive "$workspace/src" < "$manifest"
vcs log --limit 1 "$workspace/src"

