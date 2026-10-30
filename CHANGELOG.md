# Changelog

## 0.6.0 — Tutorials and editor task pinning

- Added an MIT `LICENSE` and aligned the user/developer documentation with it.
- Added first-run Essentials onboarding with a persistent, version-independent marker in the Neovim data directory.
- Added separate Essentials and Advanced tutorial menus, lesson lists, completion state, and independent reset actions.
- Added `:HyperMaxTutorial`, `<leader>+T`, and Tutorials entries in the main menu, workspace home, and command palette.
- Added persistent editor winbar summaries for pinned project tasks; the display refreshes immediately on pin/unpin and is restored when no tasks remain.
- Fixed recent-project ordering when timestamps are equal and accepted full window-position names such as `north-west`.
- Corrected dashboard tests to assert absent entries as `nil`, not literal `false`.

## 0.5.0 — Workspace history, settings and UI refinement

- Added hard save points, automatic soft saves after successful run configurations, optional Brotli compression, and a guarded rollback workflow with pre-restore safety snapshots.
- Added project-scoped diagnostics collection and quickfix navigation in `diagnostics.lua`; removed the empty, misspelled `diagonstics.lua` module.
- Added shared floating-window placement for cardinal, corner and centered context positions.
- Added persistent task pinning and configurable pinned-section placement.
- Added project-local workspace settings for entry points, hidden files, path exclusions, tabline visibility, context placement and automatic saves.
- Reworked Settings into nested categories with Back navigation, made progress windows closable with `q` or Escape, and fixed the open-after-creation window transition.
- Added regression tests and updated user/developer documentation.

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
