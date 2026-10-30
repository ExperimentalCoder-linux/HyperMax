# Changelog

## 0.4.1 — Test reliability fixes

- Corrected project-index tests to compare canonical absolute paths consistently.
- Corrected layout-exclusion assertions to distinguish an absent entry from the literal boolean `false`.
- Fixed dashboard test cleanup scope so module state is restored safely.
- Isolated test-run project registry writes in a temporary directory to protect the developer's real project index.

## 0.4.0 — Workspace and developer-flow upgrade

- Added a central floating workspace home and discoverable command palette.
- Added project-aware file finding, ripgrep text search, TODO/FIXME scanning and diagnostic quickfix navigation.
- Added a project-local task board with todo/doing/done states and priority tracking.
- Added named build, test, format and launch configurations with project-relative working-directory validation and explicit execution.
- Added run-result persistence and hardened `.hmc` metadata handling against symlinked project metadata directories/files.
- Improved floating-window transitions so navigation, quickfix, file opens and terminals do not remain hidden under a workspace overlay.
- Expanded workspace UI tests and developer documentation.

## 0.3.0 — Project and layout overhaul

- Added reusable layout capture with editable JSON drafts.
- Added global project registration and project metadata for converted folders.
- Expanded Git actions and project discovery.
