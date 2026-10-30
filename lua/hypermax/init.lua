-- Public HyperMax API.
-- This module intentionally does not import feature modules at file scope.
-- Each feature is required only when its command or public function is used.

---@class HyperMax.SavePoint
---@field id string Stable save-point identifier.
---@field kind "hard"|"soft" Save-point type.
---@field label string User-facing save-point label.
---@field created_at integer Unix timestamp.
---@field files integer Number of captured files.
---@field directories integer Number of captured directories.
---@field bytes integer Captured file bytes before compression.
---@field skipped integer Number of paths that could not be captured.
---@field compression "brotli"|"none" Storage compression format.

---@class HyperMax
---@field version string Installed semantic version.
---@field setup fun(options?: HyperMax.ConfigOverrides): HyperMax Configure preferences without initializing runtime features.
---@field initialize fun(): HyperMax Initialize commands, mappings and runtime hooks.
---@field is_initialized fun(): boolean Whether runtime initialization completed.
---@field get_config fun(): HyperMax.Config Return validated active configuration.
---@field get_version fun(): string Return installed version.
---@field create_project fun() Open the project creation wizard.
---@field save_layout fun() Capture the current directory as a layout draft.
---@field open_settings fun() Open global and project-specific settings.
---@field open_workspace fun() Open the workspace home.
---@field open_palette fun() Open the workspace action palette.
---@field open_tasks fun() Open the current project's task board.
---@field open_runs fun() Open project run configurations.
---@field open_diagnostics fun() Open project-scoped diagnostics.
---@field open_history fun() Open project save history.
---@field open_tutorials fun() Open the tutorial selector.
---@field save_point fun(): boolean, HyperMax.SavePoint|string Create a hard save point.
---@field list_projects fun() List registered projects.
---@field open_last_project fun() Open the most recently used project.
---@field quick_create_project fun() Create a project using preferred defaults.
---@field load_layout fun() Choose and apply a saved layout.
---@field edit_layout fun() Open an existing layout in the draft editor.
---@field list_layouts fun() Choose a layout for project creation.
---@field check_health fun() Run Neovim's HyperMax health check.
local HyperMax = {}

HyperMax.version = "0.7.1"

---@type boolean
local initialized = false

---@return table
---@return table config_module
local function Get_Config_Module()
	return require("hypermax.config")
end

---@param message string
---@param level? integer
local function Notify(message, level)
	vim.notify("HyperMax: " .. message, level or vim.log.levels.INFO)
end

---@return nil
local function Register_Commands()
	local registered = require("hypermax.commands").setup(HyperMax)
	if not registered then
		-- A command owned by the user or another plugin must win. Keep the rest
		-- of HyperMax available through its <Plug> mappings and public Lua API.
		Notify(
			"Could not register :HyperMax because that command is already in use. "
				.. "HyperMax has kept the existing command; use its <Plug> mappings instead.",
			vim.log.levels.WARN
		)
	end
end

---@param path any
---@return string|nil
local function Normalize_Path(path)
	if type(path) ~= "string" or path == "" then
		return nil
	end
	return vim.fn.fnamemodify(vim.fn.expand(path), ":p"):gsub("[\\/]+$", "")
end

---@param path any
---@return string|nil
local function Find_Project_Root(path)
	path = Normalize_Path(path)
	if not path then
		return nil
	end

	if vim.fn.isdirectory(path) ~= 1 then
		path = vim.fn.fnamemodify(path, ":h")
	end

	while path and path ~= "" do
		if vim.fn.isdirectory(path .. "/.hmc") == 1 then
			return path
		end
		local parent = vim.fn.fnamemodify(path, ":h")
		if parent == path then
			break
		end
		path = parent
	end

	return nil
end

---@return nil
local function Setup_Lazy_Project_Listeners()
	local group = vim.api.nvim_create_augroup("HyperMaxLazyProjectFeatures", { clear = true })
	local overlay_initialized = false

	---@param buffer? integer
	local function Maybe_Setup_Task_Overlay(buffer)
		if overlay_initialized then
			return
		end

		if not buffer or buffer == 0 then
			buffer = vim.api.nvim_get_current_buf()
		end
		if not vim.api.nvim_buf_is_valid(buffer) then
			return
		end

		local path = vim.api.nvim_buf_get_name(buffer)
		if path == "" then
			path = vim.fn.getcwd()
		end
		if not Find_Project_Root(path) then
			return
		end

		local ok, Overlay = pcall(require, "hypermax.task_overlay")
		if not ok then
			Notify("Could not load pinned-task display: " .. tostring(Overlay), vim.log.levels.WARN)
			return
		end

		local setup_ok, setup_error = pcall(Overlay.Setup)
		if setup_ok then
			overlay_initialized = true
		else
			Notify("Could not initialize pinned-task display: " .. tostring(setup_error), vim.log.levels.WARN)
		end
	end

	vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "DirChanged", "VimEnter" }, {
		group = group,
		callback = function(args)
			Maybe_Setup_Task_Overlay(args and args.buf)
		end,
	})

	-- Plugins can be loaded after VimEnter by a plugin manager. Check the
	-- current buffer immediately in that case instead of waiting for an event
	-- that has already happened.
	if vim.v.vim_did_enter == 1 then
		vim.schedule(Maybe_Setup_Task_Overlay)
	end
end

---@return boolean
local function Has_Completed_Startup_Tutorial()
	local path = vim.fn.stdpath("data") .. "/hypermax/tutorial_progress.json"
	if vim.fn.filereadable(path) ~= 1 then
		return false
	end

	local read_ok, lines = pcall(vim.fn.readfile, path)
	if not read_ok then
		return false
	end

	local decode_ok, data = pcall(vim.json.decode, table.concat(lines, "\n"))
	return decode_ok and type(data) == "table" and data.first_run_completed == true
end

---@return nil
local function Startup_Callback()
	local current_root = Find_Project_Root(vim.fn.getcwd())

	if not current_root and vim.fn.argc() > 0 then
		current_root = Find_Project_Root(vim.fn.argv(0))
	end

	if current_root then
		vim.cmd("tcd " .. vim.fn.fnameescape(current_root))
		local ok, Dashboard = pcall(require, "hypermax.dashboard")
		if ok then
			local opened, open_error = pcall(Dashboard.Open, current_root)
			if not opened then
				Notify("Could not open project dashboard: " .. tostring(open_error), vim.log.levels.WARN)
			end
		else
			Notify("Could not load project dashboard: " .. tostring(Dashboard), vim.log.levels.WARN)
		end
	end

	-- Avoid loading the tutorial module at all on normal subsequent startups.
	-- Its marker lives outside the plugin checkout, so plugin updates do not
	-- cause the welcome lesson to replay.
	if not Has_Completed_Startup_Tutorial() then
		local ok, Tutorial = pcall(require, "hypermax.tutorial")
		if ok then
			local startup_ok, startup_error = pcall(Tutorial.Setup_Startup)
			if not startup_ok then
				Notify("Could not initialize the welcome tutorial: " .. tostring(startup_error), vim.log.levels.WARN)
			end
		else
			Notify("Could not load tutorials: " .. tostring(Tutorial), vim.log.levels.WARN)
		end
	end
end

---@return nil
local function Register_Startup_Autocmds()
	Setup_Lazy_Project_Listeners()

	local group = vim.api.nvim_create_augroup("HyperMaxStartup", { clear = true })
	local function Run()
		vim.schedule(function()
			local ok, err = pcall(Startup_Callback)
			if not ok then
				Notify("Startup initialization failed: " .. tostring(err), vim.log.levels.WARN)
			end
		end)
	end

	if vim.v.vim_did_enter == 1 then
		Run()
	else
		vim.api.nvim_create_autocmd("VimEnter", {
			group = group,
			once = true,
			callback = Run,
		})
	end
end

---Configure HyperMax. This function only validates and stores options; runtime
---initialization is performed automatically by plugin/hypermax.lua.
---@param options? HyperMax.ConfigOverrides
---@return HyperMax
function HyperMax.setup(options)
	Get_Config_Module().setup(options)
	if initialized then
		require("hypermax.keymaps").Refresh_Default_Mapping()
	end
	return HyperMax
end

---Initialize runtime commands, lightweight mappings and deferred startup hooks.
---This is called automatically by the Neovim runtime plugin entry point.
---@return HyperMax
function HyperMax.initialize()
	if initialized then
		return HyperMax
	end

	Get_Config_Module().initialize()
	Register_Commands()
	require("hypermax.keymaps").Setup()
	Register_Startup_Autocmds()

	initialized = true
	return HyperMax
end

---Return the active validated global configuration.
---@return HyperMax.Config
function HyperMax.get_config()
	return Get_Config_Module().initialize()
end

---Return the installed HyperMax version.
---@return string
function HyperMax.get_version()
	return HyperMax.version
end

---Return whether the runtime entry point has initialized HyperMax.
---@return boolean
function HyperMax.is_initialized()
	return initialized
end

---Open the project creation wizard.
function HyperMax.create_project()
	require("hypermax.project").Create(HyperMax.get_config())
end

---Capture the current directory as a reusable layout.
function HyperMax.save_layout()
	require("hypermax.project").Save_Layout()
end

---Open global and project-specific settings.
function HyperMax.open_settings()
	require("hypermax.settings").Open()
end

---Open the workspace home.
function HyperMax.open_workspace()
	require("hypermax.workspace").Open()
end

---Open the workspace command palette.
function HyperMax.open_palette()
	require("hypermax.workspace").Palette()
end

---Open the current project's task board.
function HyperMax.open_tasks()
	require("hypermax.flow").Open_Tasks()
end

---Open project run configurations.
function HyperMax.open_runs()
	require("hypermax.flow").Open_Runners()
end

---Open diagnostics scoped to the current project.
function HyperMax.open_diagnostics()
	require("hypermax.workspace").Diagnostics()
end

---Open the current project save history.
function HyperMax.open_history()
	return require("hypermax.history").Open()
end

---Open the Essentials and Advanced tutorial menu.
function HyperMax.open_tutorials()
	return require("hypermax.tutorial").Open_Menu()
end

---Create a hard save point for the current project.
function HyperMax.save_point()
	return require("hypermax.history").Save(nil, "hard")
end

---List registered HyperMax projects.
function HyperMax.list_projects()
	return require("hypermax.project").List()
end

---Open the most recently opened HyperMax project.
function HyperMax.open_last_project()
	return require("hypermax.project").Open_Last()
end

---Create a project using the configured preferred defaults.
function HyperMax.quick_create_project()
	return require("hypermax.project").Quick_Create()
end

---Choose and apply a saved project layout.
function HyperMax.load_layout()
	return require("hypermax.project").Load_Layout()
end

---Open an existing saved layout in the editable draft workflow.
function HyperMax.edit_layout()
	return require("hypermax.project").Edit_Layout()
end

---Choose and create a project from one of the available layouts.
function HyperMax.list_layouts()
	local Layouts = require("hypermax.layouts")
	local choices = {}
	for _, id in ipairs(Layouts.Get_IDs()) do
		local layout = Layouts.Get(id)
		if layout then
			choices[#choices + 1] = layout
		end
	end
	if #choices == 0 then
		Notify("No layouts are available", vim.log.levels.WARN)
		return
	end
	vim.ui.select(choices, {
		prompt = "Choose layout",
		format_item = function(layout)
			local name = layout.name or layout.id
			if layout.description and layout.description ~= "" then
				return name .. " — " .. layout.description
			end
			return name
		end,
	}, function(layout)
		if layout then
			local options = vim.tbl_deep_extend("force", {}, HyperMax.get_config(), { default_layout = layout.id })
			require("hypermax.project").Create(options)
		end
	end)
end

---Run Neovim's standard HyperMax health report.
function HyperMax.check_health()
	return vim.cmd("checkhealth hypermax")
end

return HyperMax
