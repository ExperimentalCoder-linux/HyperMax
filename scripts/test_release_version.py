"""Unit tests for strict SemVer and release metadata validation."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("check_release_version.py")
SPEC = importlib.util.spec_from_file_location("check_release_version", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


class SemVerTests(unittest.TestCase):
    def test_accepts_valid_versions(self) -> None:
        for value in (
            "0.0.0",
            "0.7.1",
            "1.2.3",
            "1.2.3-alpha",
            "1.2.3-alpha.1",
            "1.2.3-0",
            "1.2.3+build.01",
            "1.2.3-rc.1+build.9",
        ):
            with self.subTest(value=value):
                self.assertTrue(CHECKER.is_valid_semver(value))

    def test_rejects_leading_zero_numeric_versions(self) -> None:
        for value in ("00.1.0", "1.01.0", "1.0.01"):
            with self.subTest(value=value):
                self.assertFalse(CHECKER.is_valid_semver(value))

    def test_rejects_leading_zero_numeric_prerelease_identifiers(self) -> None:
        for value in ("1.2.3-00", "1.2.3-alpha.01", "1.2.3-rc.0001"):
            with self.subTest(value=value):
                self.assertFalse(CHECKER.is_valid_semver(value))

    def test_rejects_malformed_versions(self) -> None:
        for value in (
            "1.2",
            "1.2.3-",
            "1.2.3+",
            "1.2.3-alpha..1",
            "1.2.3+build..9",
            "v1.2.3",
            "1.2.3-α",
            "1.2.3/other",
            "١.2.3",
        ):
            with self.subTest(value=value):
                self.assertFalse(CHECKER.is_valid_semver(value))

    def test_release_metadata_must_match(self) -> None:
        valid, message = CHECKER.validate_release(
            "v0.7.1", "0.7.1", "# Changelog\n\n## 0.7.1 — Patch release\n"
        )
        self.assertTrue(valid, message)

    def test_release_tag_must_match_source_version(self) -> None:
        valid, message = CHECKER.validate_release(
            "v0.7.2", "0.7.1", "## 0.7.1 — Patch release\n"
        )
        self.assertFalse(valid)
        self.assertIn("does not match", message)

    def test_release_requires_a_matching_changelog_heading(self) -> None:
        valid, message = CHECKER.validate_release("0.7.1", "0.7.1", "## Unreleased\n")
        self.assertFalse(valid)
        self.assertIn("no release heading", message)


if __name__ == "__main__":
    unittest.main()
