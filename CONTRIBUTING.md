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
6. Update `README.md` or `doc/README.md` when commands, configuration, or supported combinations change.

## Safety expectations

- Never overwrite existing user files without an explicit, documented confirmation flow.
- Validate project-relative paths at the operation boundary; do not rely on UI validation alone.
- Rollback may remove only artifacts created by the current operation.
- Report cleanup failures and the paths that remain.
- Treat cancellation separately from failure.
- Do not claim a language/manager combination is verified unless tests actually exercise it.

## Bug reports

Include the Neovim version, operating system, relevant language and manager, exact steps to reproduce, expected and actual behavior, and the complete error message where possible. Remove secrets and private project contents before sharing logs.
