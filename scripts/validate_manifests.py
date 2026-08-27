#!/usr/bin/env python3
"""Validate immutable vcstool manifests and release metadata."""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
SHA = re.compile(r"^[0-9a-f]{40}$")
SSH_URL = re.compile(r"^git@github\.com:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$")
CORE = {
    "SCAN-Planner",
    "omni_docking",
    "omni_mission_manager",
    "omni_robot_bridge",
    "omni_robot_interfaces",
    "omni_slam",
    "omni_tf_manager",
    "vbot_ros2_msgs",
}
FULL_STACK = CORE | {"omni-inspection", "rosdeck"}


def load_yaml(path: Path) -> object:
    with path.open("r", encoding="utf-8") as stream:
        return yaml.safe_load(stream)


def validate_manifest(path: Path, expected: set[str]) -> None:
    document = load_yaml(path)
    if not isinstance(document, dict) or set(document) != {"repositories"}:
        raise ValueError(f"{path}: top level must contain only 'repositories'")
    repositories = document["repositories"]
    if not isinstance(repositories, dict) or set(repositories) != expected:
        raise ValueError(f"{path}: repository set does not match the product profile")

    urls: set[str] = set()
    for name, spec in repositories.items():
        if not isinstance(spec, dict) or set(spec) != {"type", "url", "version"}:
            raise ValueError(f"{path}: invalid fields for {name}")
        if spec["type"] != "git":
            raise ValueError(f"{path}: {name} must use type=git")
        if not isinstance(spec["url"], str) or not SSH_URL.fullmatch(spec["url"]):
            raise ValueError(f"{path}: invalid GitHub SSH URL for {name}")
        if spec["url"] in urls:
            raise ValueError(f"{path}: duplicate URL {spec['url']}")
        urls.add(spec["url"])
        if not isinstance(spec["version"], str) or not SHA.fullmatch(spec["version"]):
            raise ValueError(f"{path}: {name} is not pinned to a 40-character SHA")


def validate_release(path: Path) -> None:
    document = load_yaml(path)
    if not isinstance(document, dict):
        raise ValueError(f"{path}: release document must be a mapping")
    required = {
        "schema_version",
        "product",
        "release",
        "status",
        "ros_distribution",
        "platforms",
        "source_manifest",
        "notes",
        "quality_gates",
    }
    if set(document) != required:
        raise ValueError(f"{path}: release fields differ from schema")
    if document["schema_version"] != 1 or document["product"] != "omni_navi":
        raise ValueError(f"{path}: unsupported schema or product")
    manifest = ROOT / str(document["source_manifest"])
    if not manifest.is_file():
        raise ValueError(f"{path}: source manifest does not exist: {manifest}")
    gates = document["quality_gates"]
    if not isinstance(gates, dict) or not gates:
        raise ValueError(f"{path}: quality_gates must be a non-empty mapping")
    allowed = {"pending", "required", "passed", "failed", "waived"}
    invalid = {str(value) for value in gates.values()} - allowed
    if invalid:
        raise ValueError(f"{path}: invalid quality gate states: {sorted(invalid)}")


def main() -> int:
    try:
        validate_manifest(ROOT / "manifests/omni_navi.lock.repos", CORE)
        validate_manifest(ROOT / "manifests/omni_full_stack.lock.repos", FULL_STACK)
        releases = sorted((ROOT / "releases").glob("*.yaml"))
        if not releases:
            raise ValueError("at least one release candidate document is required")
        for release in releases:
            validate_release(release)
    except (OSError, ValueError, yaml.YAMLError) as exc:
        print(f"manifest validation failed: {exc}", file=sys.stderr)
        return 1
    print(f"validated 2 manifests and {len(releases)} release document(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
