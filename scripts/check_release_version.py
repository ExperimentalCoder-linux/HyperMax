#!/usr/bin/env python3
"""Validate that a pushed release tag matches the plugin's SemVer version."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

_NUMERIC_IDENTIFIER = r"(?:0|[1-9][0-9]*)"
_PRERELEASE_IDENTIFIER = (
    rf"(?:{_NUMERIC_IDENTIFIER}|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)"
)
SEMVER = re.compile(
    rf"^(?P<major>{_NUMERIC_IDENTIFIER})\."
    rf"(?P<minor>{_NUMERIC_IDENTIFIER})\."
    rf"(?P<patch>{_NUMERIC_IDENTIFIER})"
    rf"(?:-(?P<prerelease>{_PRERELEASE_IDENTIFIER}"
    rf"(?:\.{_PRERELEASE_IDENTIFIER})*))?"
    r"(?:\+(?P<build>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
)


def is_valid_semver(value: str) -> bool:
    """Return whether *value* follows SemVer 2.0.0 exactly."""
    return isinstance(value, str) and SEMVER.fullmatch(value) is not None


def validate_release(tag: str, version: str, changelog: str) -> tuple[bool, str]:
    """Validate tag syntax, source version, and the matching changelog heading."""
    tag_version = tag[1:] if tag.startswith("v") else tag
    if not is_valid_semver(tag_version):
        return False, f"Release tag is not valid SemVer: {tag}"

    if not is_valid_semver(version):
        return False, f"HyperMax.version is not valid SemVer: {version}"

    if version != tag_version:
        return False, f"Release tag {tag} does not match HyperMax.version {version}"

    release_heading = re.compile(
        rf"^##\s+{re.escape(version)}(?:\s|$)", re.MULTILINE
    )
    if release_heading.search(changelog) is None:
        return False, f"CHANGELOG.md has no release heading for version {version}"

    return True, f"Release metadata is consistent for {tag} (HyperMax {version})."


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: check_release_version.py <git-tag>", file=sys.stderr)
        return 2

    tag = sys.argv[1]
    init_file = ROOT / "lua" / "hypermax" / "init.lua"
    source = init_file.read_text(encoding="utf-8")
    version_match = re.search(r'HyperMax\.version\s*=\s*"([^"]+)"', source)
    if version_match is None:
        print("Could not find HyperMax.version in lua/hypermax/init.lua", file=sys.stderr)
        return 1

    changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    valid, message = validate_release(tag, version_match.group(1), changelog)
    print(message, file=sys.stdout if valid else sys.stderr)
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
