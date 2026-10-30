-- Neovim's standard :checkhealth integration for HyperMax.
-- This module is only loaded when the user explicitly runs :checkhealth.

---@class HyperMax.Health
---@field check fun(): nil
local Health = {}

---@param name string
---@return boolean
local function Has_Executable(name)
	return vim.fn.executable(name) == 1
end

---@param name string
---@param purpose string
---@param required boolean
local function Report_Executable(name, purpose, required)
	if Has_Executable(name) then
		vim.health.ok(name .. " is available (" .. purpose .. ")")
	elseif required then
		vim.health.error(name .. " is required for " .. purpose)
	else
		vim.health.info(name .. " is optional; " .. purpose .. " will be unavailable or use a fallback")
	end
end

---@return nil
local function Check_Neovim()
	vim.health.start("Neovim compatibility")

	local version = vim.version()
	if version.major > 0 or version.minor >= 10 then
		vim.health.ok(string.format("Neovim %d.%d.%d is supported", version.major, version.minor, version.patch))
	else
		vim.health.error(
			string.format("Neovim %d.%d.%d is older than the supported minimum (0.10.0)", version.major, version.minor, version.patch),
			{ "Upgrade Neovim to 0.10.0 or newer." }
		)
	end

	if vim.health and vim.health.start then
		vim.health.ok("Using Neovim's built-in Lua and health APIs")
	end
end

---@return nil
local function Check_Runtime()
	vim.health.start("Runtime initialization")

	if vim.g.loaded_hypermax then
		vim.health.ok("HyperMax runtime entry point initialized")
	else
		vim.health.warn(
			"HyperMax runtime entry point has not initialized",
			{ "Ensure the repository is on runtimepath and plugin loading is enabled." }
		)
	end

	local ok, HyperMax = pcall(require, "hypermax")
	if not ok then
		vim.health.error("Could not load the public module: " .. tostring(HyperMax))
		return
	end

	if type(HyperMax.initialize) == "function" then
		vim.health.ok("Public API is available")
	else
		vim.health.error("Public API is missing initialize()")
	end

	vim.health.info("HyperMax version: " .. tostring(HyperMax.get_version and HyperMax.get_version() or "unknown"))
end

---@return nil
local function Check_Configuration()
	vim.health.start("Configuration")

	local ok, Config = pcall(require, "hypermax.config")
	if not ok then
		vim.health.error("Could not load configuration module: " .. tostring(Config))
		return
	end

	local options_ok, options = pcall(Config.initialize)
	if not options_ok or type(options) ~= "table" then
		vim.health.error("Configuration could not be initialized: " .. tostring(options))
		return
	end

	local valid, issues = Config.validate(options)
	if valid then
		vim.health.ok("Active global configuration fields have valid types")
	else
		for _, issue in ipairs(issues) do
			vim.health.error(issue.field .. ": " .. issue.message)
		end
	end

	for _, issue in ipairs(Config.issues or {}) do
		vim.health.warn(
			tostring(issue.source or "Configuration") .. "." .. issue.field .. ": " .. issue.message,
			{ "Correct the setting in the corresponding source; invalid values are ignored." }
		)
	end

	if type(options.project_dir) ~= "string" or options.project_dir == "" then
		vim.health.error("project_dir must be a non-empty path")
	elseif vim.fn.isdirectory(options.project_dir) == 1 then
		vim.health.ok("Project directory exists: " .. options.project_dir)
	elseif options.create_missing_dir then
		vim.health.info("Project directory will be created when needed: " .. options.project_dir)
	else
		vim.health.warn(
			"Project directory does not exist: " .. options.project_dir,
			{ "Create the directory or enable create_missing_dir." }
		)
	end

	local data_directory = vim.fn.stdpath("data")
	local writable = vim.uv and vim.uv.fs_access and vim.uv.fs_access(data_directory, "W")
	if writable then
		vim.health.ok("Neovim data directory is writable")
	else
		vim.health.warn("Could not confirm that the Neovim data directory is writable: " .. data_directory)
	end
end

---@return nil
local function Check_External_Dependencies()
	vim.health.start("External dependencies")

	Report_Executable("git", "Git integration", false)
	Report_Executable("rg", "fast project text search (filesystem fallback is used when possible)", false)
	Report_Executable("brotli", "compressed project save points (uncompressed snapshots remain available)", false)
end

---@return nil
local function Check_Language_Environment()
	vim.health.start("Language and manager registries")

	local language_ok, Languages = pcall(require, "hypermax.languages")
	local manager_ok, Managers = pcall(require, "hypermax.managers")
	if not language_ok or not manager_ok then
		vim.health.error("Could not load language or manager registry")
		if not language_ok then vim.health.info(tostring(Languages)) end
		if not manager_ok then vim.health.info(tostring(Managers)) end
		return
	end

	local language_count = 0
	local language_tools = 0
	local installed_language_tools = 0
	for _, language in pairs(Languages.Get_All()) do
		language_count = language_count + 1
		if language.executable then
			language_tools = language_tools + 1
			if Has_Executable(language.executable) then
				installed_language_tools = installed_language_tools + 1
			end
		end
	end

	local manager_count = 0
	local manager_tools = 0
	local installed_manager_tools = 0
	for _, language_managers in pairs(Managers.registry) do
		for _, manager in pairs(language_managers) do
			manager_count = manager_count + 1
			if manager.executable then
				manager_tools = manager_tools + 1
				if Has_Executable(manager.executable) then
					installed_manager_tools = installed_manager_tools + 1
				end
			end
		end
	end

	vim.health.ok(string.format("%d language definitions loaded", language_count))
	vim.health.info(string.format("Language executables available: %d/%d", installed_language_tools, language_tools))
	vim.health.info(string.format("%d project-manager definitions loaded", manager_count))
	vim.health.info(string.format("Manager executables available: %d/%d", installed_manager_tools, manager_tools))

	local Config = require("hypermax.config")
	local options = Config.initialize()
	if not Languages.Exists(options.default_language) then
		vim.health.warn("Default language is not registered: " .. tostring(options.default_language))
	elseif Languages.Get_Executable(options.default_language)
		and not Has_Executable(Languages.Get_Executable(options.default_language))
	then
		vim.health.warn(
			"Default language executable is not installed: " .. tostring(Languages.Get_Executable(options.default_language)),
			{ "Install the compiler/interpreter or select another default language in HyperMax settings." }
		)
	else
		vim.health.ok("Default language is registered: " .. options.default_language)
	end

	if not Managers.Exists(options.default_language, options.default_manager) then
		vim.health.warn(
			"Default manager is not registered for "
				.. tostring(options.default_language)
				.. ": "
				.. tostring(options.default_manager)
		)
	else
		vim.health.ok("Default manager is registered for the selected language")
	end
end

---Run the standard HyperMax health report used by :checkhealth hypermax.
---@return nil
function Health.check()
	Check_Neovim()
	Check_Runtime()
	Check_Configuration()
	Check_External_Dependencies()
	Check_Language_Environment()
end

return Health
