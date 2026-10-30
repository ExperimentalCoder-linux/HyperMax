#!/usr/bin/env python3
"""Validate that a pushed release tag matches the plugin's SemVer version."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEMVER = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
    r"(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
)


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: check_release_version.py <git-tag>", file=sys.stderr)
        return 2

    tag = sys.argv[1]
    tag_version = tag[1:] if tag.startswith("v") else tag
    if not SEMVER.fullmatch(tag_version):
        print(f"Release tag is not valid SemVer: {tag}", file=sys.stderr)
        return 1

    init_file = ROOT / "lua" / "hypermax" / "init.lua"
    source = init_file.read_text(encoding="utf-8")
    version_match = re.search(r'HyperMax\.version\s*=\s*"([^"]+)"', source)
    if version_match is None:
        print("Could not find HyperMax.version in lua/hypermax/init.lua", file=sys.stderr)
        return 1

    version = version_match.group(1)
    if not SEMVER.fullmatch(version):
        print(f"HyperMax.version is not valid SemVer: {version}", file=sys.stderr)
        return 1
    if version != tag_version:
        print(
            f"Release tag {tag} does not match HyperMax.version {version}",
            file=sys.stderr,
        )
        return 1

    changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    release_heading = re.compile(rf"^##\s+{re.escape(version)}(?:\s|$)", re.MULTILINE)
    if release_heading.search(changelog) is None:
        print(
            f"CHANGELOG.md has no release heading for version {version}",
            file=sys.stderr,
        )
        return 1

    print(f"Release metadata is consistent for {tag} (HyperMax {version}).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
