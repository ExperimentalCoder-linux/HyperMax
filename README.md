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

- Interactive project-creation wizard.
- Language and project-manager registries.
- Optional reusable project layouts.
- Save the current directory structure as a layout.
- Configurable project parent directory and default selections.
- Favourite languages and remembered choices.
- Optional progress UI during generation.
- Optional generated `README.md`, `.gitignore`, credits file, and common directories.
- Keymaps and user commands for common actions.

## Installation

### lazy.nvim

To get the HyperMax working on your personal computer Enter this terminal command to make the HyperMax file

```bash
python3 -c "import os,pathlib; p=pathlib.Path(os.environ.get('LOCALAPPDATA', str(pathlib.Path.home() / '.config')) if os.name=='nt' else pathlib.Path.home()/'.config') / 'nvim' / 'lua' / 'plugins' / 'hypermax.lua'; p.parent.mkdir(parents=True,exist_ok=True); p.write_text('return {\n    {\n        \"ExperimentalCoder-linux/HyperMax\",\n        name = \"hypermax.nvim\",\n        lazy = false,\n        opts = {\n            project_dir = \"~/Code\",\n            create_missing_dir = true,\n            open_after_create = false,\n            default_language = \"c\",\n        },\n    },\n}\n'); print('Created:', p)"
```

This is the resulting file that will link your computer to the Hypermax startup

```lua
{
    "ExperimentalCoder-linux/HyperMax",
    name = "hypermax.nvim",
    lazy = false,
    opts = {
        project_dir = "~/Code",
        create_missing_dir = true,
        open_after_create = false,
        default_language = "c",
    },
}
```

HyperMax also has a Neovim runtime entry point that calls setup when the plugin is loaded. If you use the configuration above, avoid adding a second competing plugin specification for the same repository.

**Recommended:** Neovim 0.10 or newer. HyperMax uses Neovim Lua APIs including `vim.ui.select`, `vim.ui.input`, JSON helpers, and filesystem functions. A working UI provider is needed for selection and input prompts; Neovim's built-in UI is sufficient, and UI plugins can customise it.

## Quick start

1. Install HyperMax and restart Neovim or sync your plugin manager.
2. Run `:HyperMaxCreate` or press `<leader>++` to open the HyperMax menu.
3. Choose a language and a supported project manager.
4. Enter a project name and choose the destination/options requested by the wizard.
5. Review the generated files and install any required compiler, runtime, or manager yourself.

By default, HyperMax uses `~/Projects` as its project parent directory. The default language is `cpp` and the default manager is `native`; these can be changed in Settings.

## Keymaps

Mappings are created in normal mode and use your configured `mapleader`.

| Keymap | Action |
| --- | --- |
| `<leader>++` | Open the HyperMax menu |
| `<leader>+p` | List projects in the configured project directory |
| `<leader>+s` | Open settings |
| `<leader>+l` | Load/apply a saved layout |
| `<leader>+L` | Save the current directory as a layout |
| `<leader>+o` | Open the last remembered project |
| `<leader>+c` | Show current configuration |
| `<leader>+r` | Create a project using the wizard |
| `<leader>+n` | Start project creation using current configuration defaults |

If a mapping conflicts with your own setup, change or remove it in your Neovim configuration.


## Dashboard file and Git controls

When a HyperMax project is open, its persistent sidebar supports these normal-mode keys:

| Key | Action |
|---|---|
| `Enter` | Open the selected file or expand/collapse a folder |
| `a` | Create a file using a project-relative path (for example `src/player.c`) |
| `A` | Create a folder using a project-relative path |
| `s` | Cycle sorting: alphabetical → file type → modified date → created date |
| `g` | Open Git actions: status, stage all, commit, push, pull, recent commits, and initialize |
| `G` | Initialize a Git repository in this project if it is not already one |
| `r` | Refresh the tree and Git status |
| `q` | Close the sidebar |

Git decorations show untracked (`?`), added (`+`), modified (`●`), deleted (`−`), and renamed (`»`) files. Date sorting uses filesystem timestamps; on systems/filesystems that do not expose a birth time, the created-date sort falls back to the file's change time. New paths must stay inside the project, and existing files/folders are never overwritten.

## Commands

| Command | Action |
| --- | --- |
| `:HyperMaxCreate` | Open the project-creation wizard |
| `:HyperMaxSaveLayout` | Save the current directory as a layout |
| `:HyperMaxConfig` | Print the current configuration |
| `:HyperMaxSettings` | Open the settings menu |

## Layouts: reuse the way you work

A layout captures a reusable project structure, including directories and file contents. It is useful if you have a preferred layout for experiments, small games, libraries, school work, or other recurring project types.

- Use `<leader>+L` or `:HyperMaxSaveLayout` from the directory you want to capture.
- Use `<leader>+l` to choose and apply a saved layout.
- Built-in layout data is stored in `lua/hypermax/layouts.json`.
- User-saved layouts are stored in Neovim's data directory under `hypermax/layouts.json`.

## Honest trade-offs

HyperMax is intended to save repetitive setup time, but it has limitations:

- **Early-stage coverage:** a registry entry does not guarantee a fully configured, tested, production-ready build workflow for every version of every tool.
- **Not a compiler or package manager:** HyperMax creates project files; you still need the language runtime, compiler, dependencies, and external tools.
- **Generated output needs review:** you should inspect build scripts, manifests, and commands before running them. Adjust them for your platform and workflow.
- **Less specialised than dedicated tools:** a language's official CLI or a mature framework generator may offer deeper framework-specific setup, dependency management, and upgrade support.
- **Neovim UI dependency:** interactive prompts require Neovim's UI selection/input functions to work.

The benefit is consistency and convenience across projects, not a promise that every generated project will build with zero changes.

## Project structure

```text
hypermax.nvim/
├── plugin/hypermax.lua        # Neovim runtime entry point
├── lua/hypermax/
│   ├── init.lua               # Public setup and command registration
│   ├── project.lua            # Project creation workflow
│   ├── languages.lua          # Language definitions
│   ├── managers.lua           # Project-manager definitions
│   ├── layouts.lua            # Layout operations and persistence
│   ├── layouts.json           # Built-in layout data
│   ├── settings.lua            # Interactive settings
│   ├── config.lua              # Defaults and persisted configuration
│   ├── keymaps.lua             # Default keymaps
│   └── progress.lua            # Generation progress UI
└── doc/FULL_DOCUMENTATION.md  # Full user and developer guide
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

Run the complete test suite from the repository root:

```bash
nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/run.lua"
```

The focused filesystem, Git, and dashboard suites use temporary directories and exercise invalid paths, traversal attempts, existing-file collisions, nested paths, symlink escapes (where supported), Git repositories without commits, nested repositories, status parsing, UI keymaps, and dashboard refresh behaviour. Git integration tests are skipped when the `git` executable is unavailable. A passing test suite is a checkpoint, not a guarantee that every terminal/UI plugin combination behaves identically.

## Documentation and contributing

The [full documentation](hypermax.nvim/doc/README.md) has two parts:

- **User guide:** installation, keymaps, commands, settings, layouts, and troubleshooting.
- **Developer guide:** architecture, module responsibilities, generation flow, registries, persistence, extension points, and design trade-offs.

Contributions are welcome, especially tested language/manager definitions, example layouts, reproducible bug reports, and improvements to documentation. When reporting a problem, include your Neovim version, the selected language and manager, the steps to reproduce it, and any error message.

## Design goal

HyperMax is built around a simple idea: **your project setup should be reusable, visible, and under your control**. It aims to make the first few minutes of a new project faster, without hiding the resulting files or forcing you into a separate project-management application.

---

<sub>HyperMax.nvim · Open-source project starter workflow for Neovim · Early development</sub>
