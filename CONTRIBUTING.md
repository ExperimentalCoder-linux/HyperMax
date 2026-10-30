# Contributing to HyperMax

Thanks for helping improve HyperMax. Reliability and preserving existing user data take priority over adding features quickly.

## Before opening a pull request

1. Describe the user-visible problem and the expected behavior.
2. Keep changes focused; separate refactors from behavior changes where practical.
3. Add regression tests for bugs and tests for new behavior.
4. Run the complete test suite:
   ```sh
   nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/run.lua"
   ```
5. Inspect generated files and exercise failure cases, not just the happy path.
6. Update `README.md`, `doc/README.md`, and `doc/hypermax.txt` when commands, configuration, or workflows change.
7. Keep state project-local when it belongs to one project; never leak `.hmc` data into reusable layouts.
8. For external process launchers, make execution explicit, validate working directories and document trust expectations.

## Safety expectations

- Never overwrite existing user files without an explicit, documented confirmation flow.
- Validate project-relative paths at the operation boundary; do not rely on UI validation alone.
- Rollback may remove only artifacts created by the current operation.
- Report cleanup failures and the paths that remain.
- Treat cancellation separately from failure.
- Do not claim a language/manager combination is verified unless tests actually exercise it.

## Bug reports

Include the Neovim version, operating system, relevant language and manager, exact steps to reproduce, expected and actual behavior, and the complete error message where possible. Remove secrets and private project contents before sharing logs.

## Workspace architecture

`workspace.lua` owns the workspace home, command/action picker, file finder, ripgrep search, TODO/FIXME scan, project-scoped diagnostics, buffer switcher and Git status terminal. Add discoverable actions to `Actions(root)` and keep complex operations in dedicated modules rather than embedding them in UI callbacks. Diagnostics should be filtered by project root and must not silently include unrelated buffers.

`flow.lua` owns tasks and named run configurations in `.hmc/workspace.json`. It exposes normalization, persistence and mutation APIs separately from the UI so the behavior can be tested independently. When adding fields or states, update `Normalize_Data()` with backward-compatible defaults and add cases to `tests/test_flow.lua`.

Run configurations are shell commands stored as project data. They must never execute automatically on project open. Keep execution behind an explicit Run action, validate the selected working directory at both save and execution time, and reject symlink escapes outside the project root. Treat run configuration contents from untrusted repositories as untrusted input.

Project recency is stored in the global registry. Opening the project dashboard updates the display timestamp (`last_opened`) and monotonic ordering sequence (`last_open_order`); preserve the global registry boundary rather than placing machine-specific absolute project paths into `.hmc` project files.

## Test coverage

The test runner includes project lifecycle/recency tests, flow persistence and validation tests, and workspace/flow UI smoke tests in addition to the existing layout, filesystem, Git and dashboard tests. The recommended verification command remains:

```sh
nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/run.lua"
```
