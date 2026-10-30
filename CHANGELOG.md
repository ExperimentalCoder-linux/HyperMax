# Changelog

## Unreleased

## 0.7.1 — Runtime reliability and plugin compatibility

- Guarded `:HyperMax` registration with both the Neovim user-command registry and `exists()` so an existing user or plugin command is never replaced; command registration can recover if the command is later removed.
- Made the command-collision regression test verify that its test command is actually removed before creating a simulated user-owned command.
- Improved pinned-task winbar project-root matching and title visibility in narrow windows; truncation now respects display-cell width for Unicode text.
- Added regression coverage for preserving user changes to a winbar while a pinned-task overlay is active.
- Added strict SemVer 2.0.0 validation, including rejection of leading zeroes in numeric prerelease identifiers, with Python unit tests.
- Made release publication depend on release metadata, Lua 5.1 checks, Busted specifications, and a Neovim integration run passing.
- Added Neovim compatibility CI coverage for 0.10.0, 0.11.7, 0.12.6, and nightly.
- Added Busted unit specifications for configuration validation and scoped command completion/dispatch, while keeping the real-Neovim integration suite for editor and filesystem behavior.
- Added focused LuaCATS contracts for project diagnostics, floating-window options, and runtime helper functions; expanded native Vim help and contributor documentation.

## 0.7.0 — Command API and mapping hardening

- Consolidated global actions under one `:HyperMax` command with nested subcommands and completion for command groups and directory arguments.
- Removed the previous per-action global command names; the two layout-draft commands remain buffer-local to their temporary draft buffer.
- Kept command dispatch independent of feature-module imports so project, dashboard, Git, history, tutorial and workspace features load only when invoked.
- Exposed namespaced `<Plug>(HyperMax-...)` mappings for major project and workspace actions.
- Reduced automatic global mappings to one optional, conflict-safe `<leader>++` workspace mapping; users can disable it with `default_keymaps = false`.
- Preserved existing user mappings instead of replacing them, including mappings that use HyperMax's `<Plug>` names.
- Expanded LuaCATS annotations for command options, command specifications, keymaps and the public API.
- Added regression tests for command dispatch, root and nested completion, directory argument completion, mapping ownership, default-map toggling and lazy feature imports.
- Updated README, Vimdoc and developer documentation to describe the scoped command and mapping interfaces.

## 0.6.1 — Runtime and configuration foundation

- Separated `setup()` configuration from automatic runtime initialization; `setup()` now only validates and merges preferences.
- Added an idempotent `initialize()` entry point and kept `plugin/hypermax.lua` small.
- Deferred project, dashboard, workspace, Git, history, tutorial and settings modules until their features are invoked; pinned-task listeners activate only for HyperMax project buffers.
- Added LuaCATS types for the global configuration and public API, plus `.luarc.json` for Lua 5.1 analysis.
- Added configuration validation for every supported option, list element types, unknown keys, `vim.g.hypermax`, persisted settings and explicit overrides.
- Added `lua/hypermax/health.lua` for Neovim's standard `:checkhealth hypermax` integration.
- Added regression tests for configuration schema validation and the standard health report.
- Updated user and developer documentation to describe the new configuration/initialization lifecycle and the real distinction between health checks and developer tests.


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
