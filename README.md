# HyperMax.nvim

**Build a useful project starting point without leaving Neovim.**

HyperMax is a Lua-based Neovim plugin that helps you create starter projects by combining a **programming language**, a **project manager**, and an optional reusable **project layout**. Instead of manually creating the same folders and starter files every time you begin an experiment, HyperMax gives you one place to define and generate that starting structure.

> **Status:** Early development. HyperMax has a broad language/manager registry and a reusable layout system, but support and build readiness vary by entry. Treat generated projects as starting points and review their files before relying on them.

## Why HyperMax?

Starting a project often means repeating small setup tasks: creating folders, adding an entry file, writing a build or package file, and making the same personal structure you use in every project. HyperMax aims to make that repetitive setup quicker and more consistent, while keeping you inside Neovim.

### What makes it different?

- **Language + manager selection:** choose a language and, where supported, a project manager instead of being locked into one project template.
- **Reusable layouts:** save a directory structure you already like and reuse it for future projects.
- **Customisable defaults:** set your preferred project directory, default language and manager, favourite languages, and generation options.
- **Neovim-native workflow:** use commands, keymaps, and Neovim's selection/input UI rather than switching to a separate application.
- **Inspectable output:** generated projects are ordinary files and directories. HyperMax does not hide your project behind a proprietary format.
- **Designed to extend:** language definitions, manager definitions, and layouts are kept in separate modules so contributors can expand them independently.

HyperMax is not claiming to replace every language-specific official tool or specialist project generator. Its goal is to provide a **single, reusable starting workflow across many kinds of projects**, particularly for developers who repeatedly create small projects, experiments, and learning exercises.

## Features at a glance

- Interactive project-creation wizard and a global, recency-aware project registry.
- Language and project-manager registries.
- A unified workspace home, action palette, project finder and text/diagnostic navigation.
- Per-project task boards and named build/test/run configurations.
- Expanded Git workflows for branches, remotes, tags, stashes, diffs and history.
- Optional reusable project layouts.
- Save the current directory structure as a layout.
- Configurable project parent directory and default selections.
- Favourite languages and remembered choices.
- Optional progress UI during generation.
- Optional generated `README.md`, `.gitignore`, credits file, and common directories.
- Keymaps and user commands for common actions.

- First-run Essentials onboarding plus independent Essentials and Advanced tutorial tracks, with saved lesson progress.
- Persistent pinned-task summaries in the editor winbar while you work in a project.

## Installation

### lazy.nvim

Create `lua/plugins/hypermax.lua` in your Neovim configuration directory and add this plugin specification:

```lua
{
    "ExperimentalCoder-linux/HyperMax",
    name = "hypermax.nvim",
    main = "hypermax",
    lazy = false,
    opts = {
        project_dir = "~/Code",
        create_missing_dir = true,
        open_after_create = false,
        default_language = "c",
    },
}
```

HyperMax initializes automatically through its Neovim runtime entry point. The optional `setup()` call configures preferences only; it does not need to initialize the plugin. If you use the configuration above, avoid adding a second competing plugin specification for the same repository.

**Required:** Neovim 0.10.0 or newer. HyperMax uses Neovim Lua APIs including `vim.ui.select`, `vim.ui.input`, JSON helpers, and filesystem functions. A working UI provider is needed for selection and input prompts; Neovim's built-in UI is sufficient, and UI plugins can customise it. The Lazy specification sets `main = "hypermax"` explicitly so module discovery works on case-sensitive filesystems.

The CI suite checks the minimum supported release (0.10.0), the 0.11 and 0.12 stable lines, and the latest Neovim nightly. HyperMax targets Neovim's Lua 5.1 API and does not require LuaJIT-specific extensions.

## Quick start

1. Install HyperMax and restart Neovim or sync your plugin manager.
2. Run `:HyperMax project create` or press `<leader>++` to open the HyperMax workspace.
3. Choose a language and a supported project manager.
4. Enter a project name and choose the destination/options requested by the wizard.
5. Review the generated files and install any required compiler, runtime, or manager yourself.

Run `:checkhealth hypermax` (or `:HyperMax health`) to inspect the installation, global settings, optional tools, and registered language/manager executables. The developer test suite is separate and lives in `tests/`.

By default, HyperMax uses `~/Projects` as its project parent directory. The default language is `cpp` and the default manager is `native`; these can be changed in Settings.

## Keymaps

HyperMax exposes namespaced `<Plug>` mappings for common actions. By default, it installs only `<leader>++` to open the 0.7.x workspace. The default is skipped when the user already owns that mapping. The direct shortcuts from 0.6.0 are available as an opt-in compatibility setting; they are disabled by default and never replace an existing user mapping.

Enable the old shortcut set in your plugin options or through **Settings → Interface → Enable legacy 0.6.0 global shortcuts**:

```lua
{
    "ExperimentalCoder-linux/HyperMax",
    name = "hypermax.nvim",
    lazy = false,
    opts = {
        legacy_shortcuts = true,
    },
}
```

Set `legacy_shortcuts = false` to remove the compatibility shortcuts. The `<leader>++` workspace entry point remains independently controlled by `default_keymaps`. The 0.6.0 shortcut set is:

| Shortcut | Action |
|---|---|
| `<leader>+T` | Tutorials |
| `<leader>+p`, `<D-p>` | List projects |
| `<D-o>`, `<leader>+o` | Open the last project |
| `<leader>+n`, `<leader>+r` | Project creation wizard |
| `<leader>+q` | Quick-create a project |
| `<leader>+s` | Settings |
| `<leader>+H` | Save history |
| `<leader>+S` | Create a hard save point |
| `<leader>+l`, `<leader>+L` | Load/save a layout |
| `<leader>+c` | Show configuration |
| `<leader>+m` | Open workspace |
| `<leader>+t`, `<leader>+w` | Task board / run configurations |
| `<leader>+f`, `<leader>+/` | Find files / search text |
| `<leader>+x` | Project diagnostics |
| `<leader>+<Space>` | Command palette |
| `<leader>+h` | Run health check |
| `<leader>+C`, `<leader>+u`, `<leader>+X` | Convert / undo conversion / remove metadata |

For a fully custom setup, bind only the actions you want:

```lua
vim.keymap.set("n", "<leader>hp", "<Plug>(HyperMax-CreateProject)", { remap = true })
vim.keymap.set("n", "<leader>ht", "<Plug>(HyperMax-Tasks)", { remap = true })
vim.keymap.set("n", "<leader>hh", "<Plug>(HyperMax-History)", { remap = true })
```

See [Commands](#commands) for the complete command interface and `:help hypermax-keybindings` for the full `<Plug>` list. Available actions include Menu, CreateProject, ListProjects, OpenLastProject, QuickCreateProject, SaveLayout, EditLayout, LoadLayout, ListLayouts, Settings, Workspace, Palette, Tasks, Runs, Diagnostics, FindFiles, SearchText, History, SavePoint, Tutorial, Health, ConvertProject, UndoConversion, ScrapeProject, and ShowConfig.

## Dashboard file and Git controls

When a HyperMax project is open, its persistent sidebar supports these normal-mode keys:

| Key | Action |
|---|---|
| `Enter` | Open the selected file or expand/collapse a folder |
| `a` | Create a file using a project-relative path (for example `src/player.c`) |
| `A` | Create a folder using a project-relative path |
| `s` | Cycle sorting: alphabetical → file type → modified date → created date |
| `g` | Open Git actions: status, stage/unstage, commit, fetch/pull/push, branches, remotes, tags, stashes, diffs, and history |
| `G` | Initialize a Git repository in this project if it is not already one |
| `H` | Open save-point history and rollback controls |
| `h` | Toggle hidden files and folders (also saved to this project's settings) |
| `r` | Refresh the tree and Git status |
| `q` | Close the sidebar |

Git decorations show untracked (`?`), added (`+`), modified (`●`), deleted (`−`), and renamed (`»`) files. Date sorting uses filesystem timestamps; on systems/filesystems that do not expose a birth time, the created-date sort falls back to the file's change time. New paths must stay inside the project, and existing files/folders are never overwritten.

### Folder conversion shortcuts

- `:HyperMax project convert [directory]` converts an existing folder into a HyperMax project without changing its source files. It writes project identity and metadata into `.hmc/` and registers the absolute path in the global HyperMax project index.
- `:HyperMax project undo-conversion [directory]` reverses only a conversion created by HyperMax.
- `:HyperMax project scrape [directory]` removes HyperMax metadata from a project while preserving a `.hmc.backup-*` directory. This is useful when a folder should no longer be treated as a HyperMax project.

The dashboard supports `R` to rename/move an item, `x` to cut, `p` to paste into a project-relative folder, and `d` to delete after confirmation. `.git` and `.hmc` metadata paths are protected from these file operations. Legacy `.hmc` layouts such as `basic.json`, `project.json`, `settings.json`, and `files.json` are read for compatibility.

HyperMax stores a registry of project paths and recent-open information in its global data directory. `:HyperMax project convert` registers converted projects automatically, and project discovery merges the registry with projects found directly under `project_dir`. Use `:HyperMax project list` and `:HyperMax project open-last` to access those registered projects.

## Commands

HyperMax uses one scoped command with nested subcommands. Type `:HyperMax ` and press `<Tab>` to complete the available actions; nested groups also provide their own completion. Running `:HyperMax` without arguments opens the workspace.

| Command | Action |
| --- | --- |
| `:HyperMax project create` | Open the project-creation wizard. |
| `:HyperMax project list` | List registered projects. |
| `:HyperMax project open-last` | Open the most recently opened project. |
| `:HyperMax project quick-create` | Create a project using preferred defaults. |
| `:HyperMax project convert [directory]` | Convert an existing directory into a HyperMax project. |
| `:HyperMax project undo-conversion [directory]` | Undo a folder conversion while keeping its files. |
| `:HyperMax project scrape [directory]` | Remove project metadata after creating a backup. |
| `:HyperMax layout save` / `edit` / `load` / `list` | Manage reusable project layouts. |
| `:HyperMax workspace [open]` | Open the central workspace. |
| `:HyperMax workspace palette` | Open the command palette. |
| `:HyperMax workspace tasks` / `runs` / `diagnostics` | Open project task, run, or diagnostics tools. |
| `:HyperMax workspace find-files` | Find a file in the current project. |
| `:HyperMax workspace search-text` | Search project text and send matches to quickfix. |
| `:HyperMax history [open]` | Browse project save points and rollbacks. |
| `:HyperMax history save` | Create a manual hard save point. |
| `:HyperMax settings` | Open HyperMax settings. |
| `:HyperMax config` | Print the active configuration. |
| `:HyperMax tutorial` | Open Essentials and Advanced tutorials. |
| `:HyperMax health` | Run `:checkhealth hypermax`. |

The layout-draft buffer also provides the buffer-local `:HyperMaxLayoutSave` and `:HyperMaxLayoutCancel` commands to validate/save or discard the current draft. These are scoped to the temporary layout buffer. HyperMax never replaces an existing user command named `:HyperMax`; if that name is already in use, initialization continues and the plugin's `<Plug>` mappings and public Lua API remain available.

**Command migration:** global per-action commands from earlier releases are no longer registered. Use the corresponding `:HyperMax` subcommand instead (for example, `:HyperMax project create`, `:HyperMax layout save`, or `:HyperMax history save`). The two layout-draft commands above remain buffer-local because they only apply while their draft buffer is open.


## Tutorials and first-run onboarding

On the first Neovim startup after HyperMax is installed, a welcome lesson from **Essentials** opens automatically. It introduces the everyday project workflow and the main commands. The first-run marker is saved in `stdpath("data")/hypermax/tutorial_progress.json`; it is not tied to the HyperMax version, so installing plugin updates will not show the introduction again.

Run `:HyperMax tutorial` or choose Tutorials from the workspace to open the tutorial menu. It contains two separate tracks:

- **Essentials** covers the dashboard, projects, editing/saving files, tasks, run configurations, settings, and common commands.
- **Advanced** covers reusable layouts, Git, save points and rollback, diagnostics, project workspace settings, pinned tasks in the editor, and project search/markers.

Each track has its own lessons and completion state. Mark a lesson complete with `c`; use `n` and `p` to move between lessons, and `b` to return to the lesson list. From a track list, `r` resets only that track. Resetting Advanced does not reset Essentials, and neither reset changes the one-time first-run marker.

### Pinned tasks while editing

In the task board (`:HyperMax workspace tasks`), select a task and press `P`. A summary of pinned tasks appears in the editor winbar for buffers belonging to that project and remains visible while you scroll. Press `P` again to unpin it. The winbar is restored when there are no pinned tasks; a custom winbar expression is left untouched.

## Workspace home, task flow and run configurations

HyperMax has a central workspace view that brings common project actions into one place. Open it with `:HyperMax workspace`. The command palette (`:HyperMax workspace palette`) exposes the same actions through Neovim's `vim.ui.select` interface, so UI selector plugins can enhance it without a hard dependency.

The workspace includes project switching and creation, the project explorer, recent projects, a task board, run configurations, file finding, text search, TODO/FIXME scanning, project-scoped diagnostics, Git status, layouts, settings, and health checks. Project pickers put recently opened projects first and show the last-opened timestamp. The home screen also summarizes Git changes, open tasks, run configurations, and current editor diagnostics.

### Task board

Use `:HyperMax workspace tasks` inside a HyperMax project. Tasks have a title, optional details, one of three states (`todo`, `doing`, `done`) and a priority (`low`, `normal`, `high`). The board supports adding, editing, moving, reprioritising, completing and deleting tasks. Press `P` to pin or unpin a task; pinned tasks remain in a dedicated section at the configured top or bottom of the board. Tasks and pin state are saved per project in `.hmc/workspace.json`.

### Run configurations

Use `:HyperMax workspace runs` to create named commands such as CMake builds, test suites, formatters, or launch commands. Each configuration stores a name, command, project-relative working directory and optional description. Select a configuration and press `Enter` or `r` to launch it in a terminal split. When a run exits successfully, HyperMax creates a soft save point automatically unless the project's `auto_save_after_success` setting is disabled.

Run commands are project data and are executed only after an explicit Run action. Review commands before running them, especially when opening projects from untrusted sources. Working directories are restricted to existing paths inside the project, including real-path checks that reject symlink escapes. Configuration definitions are stored alongside the task board in `.hmc/workspace.json` and are not part of reusable layouts.

### Save points and rollback

Use `:HyperMax history save` to create a hard save point, and `:HyperMax history` to browse saved states. The history window lets you create, delete and restore save points. Before restoring, HyperMax creates a safety save of the current workspace. A rollback is refused when either the target snapshot or safety snapshot contains files it could not capture completely. Git metadata is preserved; `.hmc` project settings and workspace data are included, while `.hmc/history` is excluded to prevent recursive snapshots. Brotli compression is used when the `brotli` executable is installed; otherwise snapshots are stored uncompressed. A successful runner creates a soft save by default.

### Project-specific workspace settings

The nested Settings menu separates project creation, saving/history, layouts, interface, utilities and workspace settings. Project settings are stored in `.hmc/config.json`, while global project-generation defaults stay in Neovim's global HyperMax configuration. Workspace settings include the entry-point file/function, hidden-file visibility, relative exclude patterns, tabline visibility, context-window position, pinned-task placement and automatic save-after-success. The dashboard's `h` key toggles hidden files and persists that choice. Protected `.git` and `.hmc` metadata directories remain out of the tree; other hidden directories (including `.venv` and hidden cache folders) are revealed when the option is enabled. Context windows can be anchored to `N`, `E`, `S`, `W`, corners such as `NE`/`SW`, or centered (`NS`/`EW`/`center`).

### Search and navigation

The workspace file picker opens project files. It uses ripgrep when available and a bounded filesystem scan otherwise. Project text search uses ripgrep and populates the quickfix list with matches. Project diagnostics collect current Neovim diagnostics for buffers inside the project into quickfix. Git status opens in a terminal rooted at the current project. The workspace also offers a buffer switcher.

## Layouts: reuse the way you work

A layout captures a reusable project structure, including directories and file contents. It is useful if you have a preferred layout for experiments, small games, libraries, school work, or other recurring project types.

- Use `:HyperMax layout save` from the directory you want to capture.
- HyperMax scans the directory tree and opens a temporary JSON draft in Neovim. The draft contains relative directory paths and the text contents of captured files, so you can add, remove, or edit files before saving.
- Write the draft with `:w` or `:HyperMaxLayoutSave` to validate and save it. Use `:HyperMaxLayoutCancel` to discard it.
- Use `:HyperMax layout edit` or the main menu's **Edit saved layout** action to edit a saved template in the same draft workflow.
- Use `:HyperMax layout load` to choose and apply a saved layout.
- `.hmc` and Git metadata (`.git`, `.hg`, `.svn`) are never copied. Dependency/build/cache directories, binary files, credential files (`.env`, private keys, and package-registry credentials), and files larger than 4 MiB are skipped. Safe hidden project files such as `.gitignore`, `.editorconfig`, and `.github/` are included.
- Built-in layout data is stored in `lua/hypermax/layouts.json`.
- User-saved layouts are stored in Neovim's data directory under `hypermax/layouts.json`.

## Honest trade-offs

HyperMax is intended to save repetitive setup time, but it has limitations:

- **Early-stage coverage:** a registry entry does not guarantee a fully configured, tested, production-ready build workflow for every version of every tool.
- **Not a compiler or package manager:** HyperMax creates project files; you still need the language runtime, compiler, dependencies, and external tools.
- **Generated output needs review:** you should inspect build scripts, manifests, and commands before running them. Adjust them for your platform and workflow.
- **Not a replacement for every dedicated IDE subsystem:** deep refactoring, visual designers, integrated profilers, debugger adapters, remote development and framework-specific tooling still depend on Neovim plugins or external tools. HyperMax coordinates a developer workspace; it does not implement compilers, language servers or debuggers itself.
- **Command execution is project-authored:** inspect a run configuration before launching it, particularly when opening an untrusted repository.
- **Neovim UI dependency:** interactive prompts use Neovim's `vim.ui` selection/input functions and can be styled by compatible UI plugins.

The benefit is consistency and convenience across projects, not a promise that every generated project will build with zero changes.

## Project structure

```text
hypermax.nvim/
├── plugin/hypermax.lua        # Small automatic runtime entry point
├── .luarc.json                # Lua 5.1 / LuaLS configuration
├── lua/hypermax/
│   ├── init.lua               # Public API and automatic runtime initialization
│   ├── commands.lua           # Scoped :HyperMax command and completion
│   ├── project.lua            # Project creation workflow
│   ├── languages.lua          # Language definitions
│   ├── managers.lua           # Project-manager definitions
│   ├── layouts.lua            # Layout operations and persistence
│   ├── layouts.json           # Built-in layout data
│   ├── workspace.lua          # Workspace home, palette, search and diagnostics
│   ├── health.lua             # Standard :checkhealth hypermax report
│   ├── flow.lua               # Project task board and run configurations
│   ├── git.lua                # Git state and actions
│   ├── project_config.lua     # Project metadata and global registry
│   ├── settings.lua           # Interactive settings
│   ├── config.lua              # Validated defaults and persisted preferences
│   ├── keymaps.lua             # <Plug> mappings, default and optional legacy shortcuts
│   └── progress.lua            # Generation progress UI
└── doc/README.md             # Full user and developer guide
```

### Project metadata and entry point

Each HyperMax project stores its metadata in `.hmc/basics.json`. The `project.entry_point` object records the relative path to the entry file and the function that starts the program. For example:

```json
{
  "project": {
    "entry_point": {
      "file": "src/main.c",
      "function": "main"
    }
  }
}
```

HyperMax writes this information when creating a project, and the project panel highlights that file. Paths are relative to the project root so the project can be moved without changing the entry-point path. The dashboard opens selected files in the editor window beside the persistent left-hand panel.

## Testing

Install the Busted test runner through LuaRocks and run the pure-Lua unit specifications:

```bash
luarocks --lua-version=5.1 install busted
busted --verbose spec
```

Run the Neovim integration suite separately from the repository root:

```bash
nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/run.lua"
```

Busted covers isolated configuration and command-interface contracts. The integration suite exercises actual Neovim APIs, temporary project directories, filesystem safety, Git operations, keymaps, and dashboard behavior. Git integration tests are skipped when the `git` executable is unavailable. CI runs both suites, Lua 5.1 syntax checks, Luacheck, and Lua Language Server type checking. A passing test suite is a checkpoint, not a guarantee that every terminal/UI plugin combination behaves identically.

## Documentation and contributing

The [full documentation](doc/README.md) has two parts:

- **User guide:** installation, keymaps, commands, settings, layouts, and troubleshooting.
- **Developer guide:** architecture, module responsibilities, generation flow, registries, persistence, extension points, and design trade-offs.

Contributions are welcome, especially tested language/manager definitions, example layouts, reproducible bug reports, and improvements to documentation. When reporting a problem, include your Neovim version, the selected language and manager, the steps to reproduce it, and any error message.

HyperMax is released under the [MIT License](LICENSE).

## Design goal

HyperMax is built around a simple idea: **your project setup should be reusable, visible, and under your control**. It aims to make the first few minutes of a new project faster, without hiding the resulting files or forcing you into a separate project-management application.

---

<sub>HyperMax.nvim · Open-source project starter workflow for Neovim · Early development</sub>
