# HyperMax.nvim

HyperMax is a Neovim plugin for creating starter projects from a language, a project manager, and an optional reusable layout. It generates a starting file tree and configuration files, can show progress while generating a project, and can save an existing directory as a reusable layout.

> **Project status:** HyperMax is under active development. The repository currently includes language and manager registries, JSON-backed layouts, a settings interface, project generation, and progress UI. Not every language/manager combination necessarily has a complete or tested build workflow. Review generated files and commands before using them for important work.

## Contents

- [Part I — User guide](#part-i--user-guide)
  - [Requirements](#requirements)
  - [Installation](#installation)
  - [Keymaps](#keymaps)
  - [Commands](#commands)
  - [Creating a project](#creating-a-project)
  - [Layouts](#layouts)
  - [Settings](#settings)
  - [Generated files and safety](#generated-files-and-safety)
  - [Troubleshooting](#troubleshooting)
- [Part II — Developer guide](#part-ii--developer-guide)
  - [Architecture](#architecture)
  - [Repository structure](#repository-structure)
  - [Runtime and setup flow](#runtime-and-setup-flow)
  - [Project generation pipeline](#project-generation-pipeline)
  - [Language registry](#language-registry)
  - [Manager registry](#manager-registry)
  - [Layout data model](#layout-data-model)
  - [Configuration and persistence](#configuration-and-persistence)
  - [Module APIs](#module-apis)
  - [Path validation and file-writing policy](#path-validation-and-file-writing-policy)
  - [Extending HyperMax](#extending-hypermax)
  - [Testing and release checklist](#testing-and-release-checklist)
  - [Design decisions and trade-offs](#design-decisions-and-trade-offs)

---

# Part I — User guide

This section covers the features an everyday user needs: installation, keymaps, commands, settings, and the project-creation workflow. You do not need to understand the internal Lua modules to use HyperMax.

## Requirements

- Neovim with the Lua and `vim.*` APIs used by the plugin. The implementation uses `vim.json`, `vim.ui.select`, `vim.ui.input`, `vim.uv` (with `vim.loop` fallback), and modern window APIs; **Neovim 0.10 or newer is recommended**.
- A UI implementation for `vim.ui.select` and `vim.ui.input`. Neovim's built-in UI works, while plugins such as `dressing.nvim` or `snacks.nvim` may provide an alternative interface.
- Optional compilers, interpreters, and project-manager tools for the language/manager you choose. HyperMax can generate starter files without every tool being installed, but a selected manager may be checked for its executable.

## Installation

### With lazy.nvim

Use the repository URL in your plugin specification:

```lua
{
    "ExperimentalCoder-linux/HyperMax",
    name = "hypermax.nvim",
    config = function()
        require("hypermax").setup({
            -- Optional overrides; see Configuration below.
            project_dir = "~/Projects",
        })
    end,
}
```

If your plugin manager uses a different setup convention, install/clone the repository into a Neovim runtime plugin directory and ensure the repository's `lua/` directory is on `runtimepath`. The `plugin/hypermax.lua` entry point calls setup automatically when Neovim loads the plugin. With lazy-loading, make sure the plugin is loaded before expecting its user commands to exist.

> **Setup note:** If you use the automatic runtime entry point, you normally do not need to call `setup()` manually. Calling `require("hypermax").setup({...})` is useful when you want to provide overrides. Follow your plugin manager's loading convention and avoid defining multiple competing plugin specs for the same repository.

## Keymaps

HyperMax maps normal-mode shortcuts under `<leader>+`. The plus sign is part of the prefix: the default mappings are written as `<leader>++`, `<leader>+p`, and so on. Your actual keystrokes depend on your `mapleader` setting.

| Keymap | Action | Description |
|---|---|---|
| `<leader>++` | Open HyperMax menu | Opens a menu with project, settings, layout, and last-project actions. |
| `<leader>+p` | List projects | Scans the configured project directory and offers projects to open. |
| `<leader>+s` | Settings | Opens the interactive settings menu. |
| `<leader>+l` | Load layout | Selects a saved layout and applies it to a target project directory. |
| `<leader>+L` | Save layout | Saves the current working directory's structure as a reusable layout. |
| `<leader>+o` | Open last project | Opens the last project path remembered by HyperMax, if one is available. |
| `<leader>+c` | Show configuration | Prints the current configuration table. |
| `<leader>+r` | Create project | Starts the project-creation wizard. |
| `<leader>+n` | New project | Starts project creation using the current configuration as defaults. |

Mappings are registered in normal mode and are silent. If one conflicts with your own mapping, change or remove it in your Neovim configuration.

## Commands

| Command | Action |
|---|---|
| `:HyperMaxCreate` | Start the project-creation wizard. |
| `:HyperMaxSaveLayout` | Save the current directory as a layout. |
| `:HyperMaxConfig` | Print the current HyperMax configuration. |
| `:HyperMaxSettings` | Open the interactive settings menu. |

These commands do not currently accept documented command-line arguments; selection happens through the interactive UI.

## Creating a project

1. Run `:HyperMaxCreate`, use `<leader>+r`, or choose **Projects** from `<leader>++`.
2. Select a language from the registry. Favourite languages are shown first.
3. Select a project manager supported for that language, such as `native`, `make`, or `cmake` where registered.
4. Enter the project name and confirm the destination and options presented by the wizard.
5. Optionally select a layout if prompted/configured.
6. HyperMax validates relative paths, creates the directory/file tasks, and reports progress when enabled.
7. Review the generated files. Install any required tools and adjust build, run, and test commands to match your environment.

The default project parent is `~/Projects`. The default language is `cpp`, and the default manager is `native`. These values can be changed in Settings.

## Layouts

A layout describes a reusable project structure: directories, file contents, and optional language-specific commands. Layouts can be used to make consistent structures across new projects.

- **Save current project as layout:** run `:HyperMaxSaveLayout` or press `<leader>+L` while the current working directory is the directory you want to capture.
- **Load layout:** run `<leader>+l` and select an available layout.
- Built-in layouts/data live in `lua/hypermax/layouts.json`.
- User-saved layouts are stored under Neovim's data directory at `stdpath("data") .. "/hypermax/layouts.json"`.

Layout paths are intended to be relative to the project root. Absolute paths, parent-directory traversal (`..`), and backslash-separated paths are rejected by path validation. If a layout cannot be loaded, inspect the JSON syntax and ensure file/directory paths are safe relative paths.

## Settings

Open Settings with `<leader>+s` or `:HyperMaxSettings`. Changes are persisted to:

```text
stdpath("data")/hypermax/settings.json
```

The current settings menu exposes these options:

| Setting | Default | Meaning |
|---|---|---|
| `project_dir` | `~/Projects` | Parent directory used when creating/listing projects. Expanded during setup. |
| `create_missing_dir` | `true` | Allows HyperMax to create a missing project parent directory. |
| `open_after_create` | `true` | Opens the new project after successful creation. |
| `default_language` | `cpp` | Initial/default language selection. |
| `default_manager` | `native` | Initial/default manager selection. |
| `default_layout` | `""` | Default layout ID; empty means no explicit default layout. |
| `favourite_languages` | `cpp`, `c`, `lua`, `python`, `rust` | Language IDs prioritised in language selection. |
| `show_progress` | `true` | Displays the progress window during generation. |
| `show_command_output` | `true` | Enables command-output display where the generation workflow uses it. |
| `confirm_before_create` | `true` | Requests confirmation before project creation. |
| `create_readme` | `true` | Generates `README.md` if the selected manifest does not already provide it. |
| `create_gitignore` | `true` | Generates `.gitignore` if the manifest does not already provide it. |
| `create_credits` | `true` | Enables the credits-file option in project generation. |
| `create_default_directories` | `true` | Adds `src`, `tests`, and `docs` when missing from the manifest. |
| `remember_last_language` | `true` | Remembers the last language choice. |
| `remember_last_manager` | `true` | Remembers the last manager choice. |
| `remember_last_project` | `true` | Remembers the last project path for the Open Last Project action. |

The settings menu also has **Reset all settings to defaults**. Settings are stored as JSON; if the file is invalid, HyperMax warns and falls back to defaults and valid overrides.

## Generated files and safety

Depending on the language, manager, and layout, a new project may contain:

- A language entry/source file (for example, `main.cpp` or `main.py`).
- Manager files (for example, a build configuration or package manifest).
- `README.md`, `.gitignore`, and `CREDITS.md`, when enabled and not already supplied by the selected manifest.
- Default directories such as `src/`, `tests/`, and `docs/`.
- Layout-specific files and directories.

HyperMax is a **starter generator**, not a guarantee that every generated project builds without modification. Check generated commands and manifests before running them, especially if they delete files or invoke external tools. The generator is designed to create new files rather than silently overwrite existing files. Choose a new/empty destination when possible.

## Troubleshooting

- **Commands are unknown:** confirm the plugin is installed and loaded, then restart Neovim or run your plugin manager's sync command.
- **No selection menu appears:** ensure a `vim.ui.select` provider is available and functioning.
- **A manager is unavailable:** install its executable and ensure it is on `PATH`, or select another manager supported by that language.
- **A project path is unexpected:** inspect `project_dir` in Settings and remember that `~` is expanded by Neovim.
- **A layout fails to load:** validate `layouts.json`, use unique layout IDs, and ensure all paths are safe relative paths.
- **Settings appear to reset:** inspect `stdpath("data")/hypermax/settings.json` for malformed JSON and check that the directory is writable.
- **A generated project does not build:** check the generated manifest and README, then verify the relevant compiler/runtime and manager are installed. Some registry entries have limited starter support.

---

# Part II — Developer guide

This section describes the implementation's responsibilities, module boundaries, data flow, extension points, and the reasons for the current design. It is written for contributors modifying HyperMax itself.

## Architecture

HyperMax is a Lua plugin organized around a small public entry module and specialised internal modules. The current design separates **what a language/manager/layout is** from **how a project is created** and **how the user interacts with the plugin**.

```text
Neovim runtime
    │
    ├── plugin/hypermax.lua       Runtime entry point; loads once
    │       │
    │       └── require("hypermax").setup()
    │                    │
    │                    ├── config.lua       Defaults + persisted options
    │                    ├── keymaps.lua      Normal-mode key bindings
    │                    ├── settings.lua     Interactive settings editor
    │                    ├── project.lua      Project wizard + file creation
    │                    │       ├── languages.lua
    │                    │       ├── managers.lua
    │                    │       ├── layouts.lua
    │                    │       └── progress.lua
    │                    └── layouts.lua      Layout registry + JSON I/O
    │
    └── User commands: HyperMaxCreate, HyperMaxSaveLayout,
                       HyperMaxConfig, HyperMaxSettings
```

The intended dependency direction is that the project workflow consumes registries and services, while registries should not depend on UI-specific code unless required. Lua's `require()` cache ensures each module is normally initialised once per Neovim session. Avoid creating circular dependencies: keep shared configuration in `config.lua`, registry data in registry modules, and user interaction in the UI/workflow layer.

## Repository structure

```text
hypermax.nvim/
├── README.md
├── plugin/
│   └── hypermax.lua
├── lua/
│   └── hypermax/
│       ├── init.lua
│       ├── project.lua
│       ├── languages.lua
│       ├── managers.lua
│       ├── layouts.lua
│       ├── layouts.json
│       ├── config.lua
│       ├── settings.lua
│       ├── keymaps.lua
│       ├── progress.lua
│       └── check_list.txt
├── doc/          Reserved for Vim help documentation
├── root_files/   Reserved for reusable root-level file templates
└── tests/        Reserved for automated tests
```

### File responsibilities

| File | Responsibility | Why it is separate |
|---|---|---|
| `plugin/hypermax.lua` | Neovim runtime loader; guards against duplicate loading and calls setup. | Runtime plugin scripts are discovered by Neovim; this file should be small and side-effect-limited. |
| `lua/hypermax/init.lua` | Public module, version, setup, user-command registration, and public convenience functions. | Gives users and plugin managers one stable entry point. |
| `project.lua` | Interactive creation flow, project listing/opening, last-project behavior, manifest generation, and safe file/directory creation. | Project creation is the main workflow and coordinates the other modules. |
| `languages.lua` | Language metadata and language-related queries, including default entry filenames and executable checks. | Keeps language-specific identity separate from project-generation mechanics. |
| `managers.lua` | Per-language manager registry and lookup/availability helpers. | Prevents manager logic from being scattered through project code. |
| `layouts.lua` | Built-in/user layout loading, validation, lookup, manifest building, placeholder replacement, applying/saving/deleting layouts. | Treats layouts as reusable data rather than hard-coded wizard branches. |
| `layouts.json` | Built-in defaults, credits template, language-specific command definitions, and layout data. | Lets structure and command metadata be edited without rewriting Lua control flow. |
| `config.lua` | Defaults, option merging, JSON persistence, getters/setters, and reset. | Gives all modules a single source of truth for preferences. |
| `settings.lua` | `vim.ui.select`/`vim.ui.input` interface for changing preferences. | Keeps presentation and interactive editing out of configuration storage. |
| `keymaps.lua` | `<leader>+` mappings and menu dispatch. | Makes the keyboard interface easy to modify independently. |
| `progress.lua` | Floating progress window, progress bar, current task, and recent output. | Keeps progress rendering out of the generator's filesystem logic. |
| `check_list.txt` | Development checklist. | Tracks planned work; it is not an executable test suite. |

## Runtime and setup flow

1. Neovim sources `plugin/hypermax.lua` from `runtimepath`.
2. The `vim.g.loaded_hypermax` guard prevents the runtime entry point from registering the plugin repeatedly.
3. The entry point calls `require("hypermax").setup()`.
4. `init.lua` loads the keymap, layout, config, project, and settings modules.
5. On first setup, `Config.setup(options)` merges defaults, saved settings, and caller overrides; commands and keymaps are registered.
6. Commands delegate to the corresponding module functions. For example, `:HyperMaxCreate` calls `Project.Create(Config.options)` and `:HyperMaxSaveLayout` calls `Project.Save_Layout()`.

`HyperMax.setup(options)` is designed to avoid repeating first-time registration. A later explicit call with non-`nil` options passes those options to `Config.setup`. If setup behavior is changed, preserve a clear distinction between **initial registration** and **reconfiguration**; otherwise repeated setup can create duplicate maps or unexpectedly reload persisted settings.

The public module currently exposes:

```lua
local HyperMax = require("hypermax")

HyperMax.setup({
    project_dir = "~/Projects",
    default_language = "cpp",
})

local config = HyperMax.get_config()
local version = HyperMax.get_version()
HyperMax.create_project()
HyperMax.save_layout()
HyperMax.open_settings()
```

The `get_config()` function returns the live `Config.options` table, not a defensive copy. Callers should treat it as read-only unless they intentionally want to mutate runtime state; use configuration APIs for persisted changes.

## Project generation pipeline

The project generator coordinates several distinct stages. Keeping these stages explicit makes errors easier to localise and prevents user-interface details from being mixed with file-writing code.

1. **Collect choices.** The wizard gets language IDs and display names from `languages.lua`, then available manager choices from `managers.lua`. Language favourites and remembered choices influence ordering/defaults.
2. **Resolve target.** The project name and destination are combined with the configured parent directory. Missing-parent behavior is controlled by `create_missing_dir`.
3. **Check requirements.** A selected manager may declare an executable. The generator checks for it and can inform the user if it is unavailable.
4. **Build a manifest.** A manifest is a Lua table describing relative directories, files, and an entry file. The default manifest is composed from layout defaults, a language source template, optional README/gitignore/credits content, default directories, and manager-specific files. A selected layout can provide a custom manifest.
5. **Merge missing manager/default files.** Manager files are added only when the manifest does not already provide a file at that path, so explicit layout content takes precedence.
6. **Validate paths.** Each generated file/directory path must be safe and relative. Reject absolute paths, `.`/`..` path segments, NUL characters, and backslashes.
7. **Create tasks.** Manifest entries are converted into ordered filesystem tasks with a root-relative path and full path.
8. **Write files/directories.** New files are created without intentionally overwriting existing files. Failures should be reported with the path and cause.
9. **Report progress.** If `show_progress` is enabled, `progress.lua` displays a floating window with a progress bar, current task, and recent output.
10. **Remember/open project.** According to configuration, the workflow updates last-choice/project information and opens the new project in Neovim.

A manifest separates *desired project contents* from *side effects*. That makes it possible to test the shape of a project without needing to run every compiler or package manager. Keep manifest construction deterministic where practical; tests should not rely on Lua `pairs()` ordering for file creation order.

## Language registry

`languages.lua` maintains the language-to-entry-filename map and exposes query functions. The language ID is a stable internal key such as `cpp`, `c`, `python`, or `javaScript`; it is not necessarily the display name shown to the user.

Public helpers currently include:

- `Languages.Get_All()` — returns the registry's language data.
- `Languages.Get(id)` — looks up one language.
- `Languages.Exists(id)` — checks whether an ID exists.
- `Languages.Count()` — counts registered languages.
- `Languages.Is_Installed(id)` — checks availability using the language's declared executable where available.
- `Languages.Get_Executable(id)` — returns the executable associated with a language, if defined.
- `Languages.Get_Default_File(id)` — returns the default entry filename.
- `Languages.Get_IDs()` — returns the registered IDs.

### Adding a language

1. Add a unique ID and default entry filename to the `files` table in `languages.lua`.
2. Add an entry to `Managers.registry` in `managers.lua`, at minimum a `native` manager if that makes sense for the language.
3. Add language-specific build/run/test/clean commands to `layouts.json` when reliable defaults are known. Leave command fields empty/absent if no portable command can be safely assumed.
4. Add or review the source template returned by the project generator's source-template logic. The filename alone does not guarantee a useful source template.
5. Check any language-specific manager manifest files, README naming, and layout compatibility.
6. Add tests for the ID, default filename, manager choices, generated source, and manifest output.

Use consistent IDs across all registries and JSON keys. Do not change an ID casually after users have saved favourites, defaults, or layouts that refer to it.

## Manager registry

`managers.lua` defines the manager options available per language. The registry has this shape:

```lua
Managers.registry = {
    cpp = {
        native = { name = "Native C++" },
        make = { name = "Make", executable = "make" },
        cmake = { name = "CMake", executable = "cmake" },
    },
}
```

- The first-level key is the language ID.
- The second-level key is a manager ID.
- `name` is a human-readable label.
- `executable`, when provided, identifies a command whose presence can be checked.
- `native` conventionally means no separate project manager is required; it does not mean the compiler/runtime itself is installed.

Public helpers include `Get_For_Language`, `Get`, `Is_Installed`, `Get_IDs`, `Get_Choices`, and `Exists`. Manager file-generation logic is also housed in this module; inspect its per-manager builders before adding a new manager so generated files match the selected tool and language.

### Adding a manager

1. Add it under the appropriate language ID.
2. Supply a clear label and the actual executable name used by the system.
3. Add its manifest/file builder for required project files if it needs them.
4. Ensure generated commands agree with those files and the current layout directory structure.
5. Handle missing executables without crashing the entire plugin.
6. Test both the installed and missing-executable paths.

Avoid treating the presence of a manager executable as proof that the compiler or SDK is fully configured. Availability checks should be described as preliminary checks, not complete environment validation.

## Layout data model

The built-in layout file `layouts.json` is a versioned JSON document. Its top-level data currently includes:

- `version`: layout data schema version.
- `defaults`: default directories and file templates shared by projects.
- `credits`: path and contents for the optional credits file.
- `languages`: language-specific command definitions and/or layout overrides.
- Other layout records handled by `layouts.lua` according to the validation and lookup rules.

A simplified illustration of the data shape is:

```json
{
  "version": 1,
  "defaults": {
    "directories": ["src", "tests", "docs"],
    "files": {
      "README.md": "# {{PROJECT_NAME}}\n"
    }
  },
  "credits": {
    "path": "CREDITS.md",
    "content": "# Credits\n"
  },
  "languages": {
    "cpp": {
      "build": "c++ -std=c++17 src/main.cpp -o build/app",
      "run": "./build/app",
      "test": "make test",
      "clean": "rm -rf build"
    }
  }
}
```

This is an illustrative fragment, not a complete replacement for the real file. The implementation supports placeholders such as `{{PROJECT_NAME}}` and command placeholders such as `{{BUILD_COMMAND}}`, `{{RUN_COMMAND}}`, `{{TEST_COMMAND}}`, and `{{CLEAN_COMMAND}}` in the relevant templates. Confirm supported placeholders in `layouts.lua` before introducing new ones.

`layouts.lua` is responsible for reading JSON, validating layout data, combining built-in and user layouts, looking up layouts by ID/language, producing manifests, applying layouts, and saving/deleting user layouts. Built-in data is loaded from the module's own directory; user data is stored in Neovim's data directory. Keep schema changes backward-compatible when possible. If a breaking change is necessary, increment the schema version and implement a migration or a clear error path.

### Layout authoring rules

- Use unique, stable layout IDs.
- Use relative POSIX-style paths (`src/main.cpp`), not absolute paths.
- Do not use `..`, `.` path components, drive-prefixed paths, NUL characters, or backslashes.
- Keep file content as strings and directories as arrays of strings.
- Avoid defining a manager manifest and a layout file at the same path unless the precedence is intentional; current merge logic preserves manifest/layout content and adds missing manager files.
- Treat generated commands as data that will eventually be executed by a user. Prefer transparent, conventional commands and document platform assumptions.

## Configuration and persistence

`config.lua` owns the canonical defaults and persisted option table. Its public API is:

- `Config.setup(options)` — reads saved settings, merges defaults, saved values, and explicit overrides, then expands `project_dir`.
- `Config.get(key)` — reads one setting.
- `Config.set(key, value)` — changes one setting and saves all current options.
- `Config.save()` — serialises the current options to JSON.
- `Config.reset()` — replaces options with defaults and persists them.
- `Config.get_settings_path()` — returns the settings JSON path.

Merge order is important: **defaults → saved settings → explicit setup options**. Therefore, caller-supplied setup values override persisted settings for that setup call. The project directory is expanded through `vim.fn.expand` after merging.

When adding a setting:

1. Add its default to `Config.defaults` with the correct type.
2. Decide whether it needs a settings-menu control and add it to `Boolean_Settings` or `Settings.Open()` in `settings.lua`.
3. Add handling in `Edit_Setting()` if it is not a boolean, language, favourites, manager, or text setting already supported.
4. Consume it in the relevant workflow, rather than only displaying it.
5. Document the option in the user-facing settings table and test defaults, persistence, malformed JSON, and reset behavior.

Do not store secrets in this JSON file. It is a local preference file, not a secure credential store.

## Module APIs

The following is a practical overview of currently exposed helpers. Check the source when changing contracts; internal helpers may be renamed as the plugin evolves.

### `hypermax` (`init.lua`)

- `setup(options)` — initialise configuration, commands, and keymaps.
- `get_config()` — returns the active options table.
- `get_version()` — returns the plugin version (`0.2.0` in this codebase).
- `create_project()` — starts project creation with current options.
- `save_layout()` — saves the current directory as a layout.
- `open_settings()` — opens the settings UI.

### `hypermax.project` (`project.lua`)

- `Create(user_options)` — starts the interactive project wizard; options may override active configuration.
- `Save_Layout()` — captures the current directory as a reusable layout.
- `Open_Last()` — opens the remembered project, when one exists.
- `List()` — scans the configured project directory and presents projects.
- `Load_Layout()` — selects a layout and applies it through the layout/project workflow.

The generator also contains internal functions for path safety, directory creation, manifest composition, manager checks, and opening the generated project. Keep these local unless other modules genuinely need them; a smaller public API reduces accidental coupling.

### `hypermax.layouts` (`layouts.lua`)

Notable functions include `Is_Safe_Path`, `Load_File`, `Reload`, `Get_Config`, `Get_Defaults`, `Get_Credits`, `Get_Language`, `Get_Languages`, `Get_All`, `Get`, `Exists`, `Get_IDs`, `Get_For_Language`, `Get_Commands`, `Build_Manifest`, `Apply`, `Save`, and `Delete`.

### `hypermax.languages` (`languages.lua`)

Notable functions include `Get_All`, `Get`, `Exists`, `Count`, `Is_Installed`, `Get_Executable`, `Get_Default_File`, and `Get_IDs`.

### `hypermax.managers` (`managers.lua`)

Notable functions include `Get_For_Language`, `Get`, `Is_Installed`, `Get_IDs`, `Get_Choices`, and `Exists`. The registry itself is exposed as `Managers.registry` in the current implementation.

### `hypermax.config` (`config.lua`)

Notable functions include `setup`, `get`, `set`, `save`, `reset`, and `get_settings_path`. The active options and defaults are exposed as `Config.options` and `Config.defaults`.

### `hypermax.settings` (`settings.lua`)

- `Open()` — presents the interactive settings selector.

### `hypermax.keymaps` (`keymaps.lua`)

- `Setup(Project, Settings, Layouts)` — registers the plugin's normal-mode mappings. The current function accepts `Layouts` for interface compatibility, although the current mappings dispatch through `Project` for layout actions.

### `hypermax.progress` (`progress.lua`)

- `Start(title, total)` — creates the progress UI.
- `Update(message, completed, total)` — updates progress and task text.
- `Log(message)` — appends output to the progress view.
- `Increment(message)` — increments completion.
- `Finish(success, message)` — marks the operation finished.
- `Close()` — closes/clears the progress UI.

## Path validation and file-writing policy

Project creation and layout application write to the filesystem, so path safety is part of the design rather than optional polish.

The generator validates manifest paths before joining them to the target root. The layout system separately validates paths read from layout data. These checks should reject absolute paths and traversal components so a malicious or malformed layout cannot deliberately write outside the project root. Keep validation close to the point where untrusted paths enter the filesystem pipeline, even if an earlier layer has already validated them.

The file writer is intended to create new files rather than overwrite existing content. Preserve this invariant if refactoring: accidental overwrites are destructive and difficult to reverse. When a path already exists, report the collision and choose a clear policy rather than silently truncating it. Directory creation can be idempotent; file creation should not assume that it is safe to replace an existing file.

Additional hardening worth covering with tests:

- Symlink behavior and whether resolved paths remain under the target root.
- Case sensitivity and platform path conventions.
- Permission errors and partial creation failures.
- Duplicate manifest paths and duplicate layout IDs.
- Interrupted generation and cleanup/rollback expectations.
- Handling of invalid UTF-8 or malformed JSON.
- Command execution boundaries: display generated commands clearly and do not execute arbitrary layout-supplied commands implicitly without an explicit, documented user action.

## Extending HyperMax

### Add a new language

Update the language registry, manager registry, source-template logic, and built-in JSON commands where appropriate. Then test a full manifest for that language. Do not add an ID to only one registry: the UI can offer a language whose manager/template data is missing if the registries become inconsistent.

### Add a project manager

Add a manager entry and any manager-specific manifest-generation logic. Ensure executable checks use the correct command name and that the generated files and commands agree. For example, a CMake project needs a `CMakeLists.txt` that matches the chosen source path and target name; adding only `cmake` to the registry is not a complete implementation.

### Add a layout

Add a validated layout record to the built-in JSON or use the user layout workflow. Use stable IDs and relative paths. Include files and directories that make sense for the language and selected manager, and ensure placeholders are replaced before writing.

### Add a setting

Add the default in `config.lua`, the UI entry/edit route in `settings.lua`, usage in the appropriate module, and documentation. Keep defaults backward-compatible so users with older settings files continue to work.

### Add a command or keymap

Register commands in `Register_Commands()` in `init.lua` with a descriptive `desc`. Add mappings in `keymaps.lua` through the local `Map()` helper so descriptions consistently use the `HyperMax:` prefix. Avoid registering commands in multiple modules.

## Testing and release checklist

The repository's `tests/` directory is currently present but does not contain a complete automated test suite. Before calling a change verified, run syntax and runtime checks in a real Neovim environment.

Suggested local checks:

```sh
# If luac is installed, syntax-check every Lua file.
find lua plugin -name '*.lua' -print0 | xargs -0 -n1 luac -p

# Check that the built-in layout JSON parses (Python is optional).
python3 -m json.tool lua/hypermax/layouts.json >/dev/null

# Start Neovim with the plugin on runtimepath, then inspect commands.
nvim --clean
```

Inside Neovim, verify `:HyperMaxCreate`, `:HyperMaxSaveLayout`, `:HyperMaxConfig`, and `:HyperMaxSettings`, then test each keymap. Also test project creation with an empty target, an existing target/file collision, a missing manager executable, invalid layout JSON, a layout containing an unsafe path, and a read-only parent directory.

For each release, check:

- [ ] Lua syntax checks pass for all plugin files.
- [ ] Built-in JSON parses and layout validation passes.
- [ ] Setup works both with automatic runtime loading and the documented plugin-manager configuration.
- [ ] Repeated setup does not create duplicate commands or unexpected mappings.
- [ ] Every documented command and keymap works.
- [ ] Each registered language has a default filename and sensible manager choices.
- [ ] Manager files and generated commands agree with the manifest's directory structure.
- [ ] Existing files are not overwritten unexpectedly.
- [ ] User settings and layouts survive a restart.
- [ ] Documentation matches the current implementation.
- [ ] A clean installation is tested with a supported Neovim version.

## Design decisions and trade-offs

### Why split the implementation into modules?

Project creation touches language metadata, manager metadata, layouts, persistent preferences, interactive prompts, filesystem operations, and progress rendering. Keeping those concerns in separate modules makes each part easier to inspect and change. The trade-off is that cross-module IDs and contracts must remain consistent; tests should cover these boundaries.

### Why use registries?

Language and manager registries turn choices into data instead of large chains of conditionals. This makes it easier to add entries, sort favourites, and query availability. The trade-off is that an entry may look complete in a menu while its template or manager-file generator is still incomplete. Registry consistency checks and integration tests are therefore important.

### Why use JSON for layouts and settings?

JSON is readable, editable without Lua syntax knowledge, and supported by Neovim's `vim.json` API. It also separates project structure from control flow. The trade-offs are limited data types, strict syntax, and the need to validate loaded data and handle schema changes.

### Why build a manifest before writing files?

A manifest represents the intended output before filesystem side effects begin. This makes path validation, merging defaults, adding manager files, and future dry-run/testing features easier. The trade-off is that all manifest sources must follow the same path rules and precedence policy.

### Why reject unsafe paths and avoid overwriting files?

Layouts are data that can name paths, and users may have existing work in a destination. Restricting output paths to safe relative paths reduces traversal risk; create-new-file behavior reduces accidental data loss. These protections should remain even if they add a little complexity to the writer.

### Why keep progress rendering in its own module?

The generator can report tasks without knowing how the progress window is drawn. This isolates window/buffer state from filesystem logic and allows progress UI changes without rewriting generation. The trade-off is that progress state is session-global, so concurrent generation operations would need an explicit state model.

### Current limitations to keep in mind

- Automated tests are not yet comprehensive.
- Language registry breadth is larger than the set of workflows that can be guaranteed to build on every platform.
- Build/run/test commands are platform- and toolchain-dependent; a command in the registry is a suggested default, not a universal promise.
- `get_config()` exposes the live table, so consumers can mutate options without persistence if they modify it directly.
- Layout/schema migrations and rollback of partially generated projects should be designed explicitly before introducing breaking changes.

---

## Contributing

When submitting changes, include the reason for the change, affected modules, expected behavior, and how it was tested. For cross-module features, update this README and add tests for the registry, manifest, and user-facing behavior. Keep generated files and documentation aligned with the actual implementation.

## License

No license file was present in the inspected repository at the time this README was written. Add a `LICENSE` file before presenting the project as open-source software with a specific license.
