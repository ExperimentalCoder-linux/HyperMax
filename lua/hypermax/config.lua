-- HyperMax global configuration.
-- Configuration is deliberately independent from runtime initialization:
-- setup() only validates and merges options. plugin/hypermax.lua initializes
-- the plugin automatically after configuration has had a chance to load.

---@class HyperMax.Config
---@field project_dir string Parent directory used for new projects.
---@field create_missing_dir boolean Create project_dir when it does not exist.
---@field open_after_create boolean Open a project after creating it.
---@field default_language string Default language registry ID.
---@field default_manager string Default project-manager registry ID.
---@field default_layout string Default layout ID, or an empty string.
---@field last_project_path string Last opened project path.
---@field favourite_languages string[] Preferred language IDs shown first.
---@field remember_last_project boolean Remember the last opened project.
---@field show_progress boolean Display project creation progress.
---@field show_command_output boolean Display external command output.
---@field confirm_before_create boolean Ask before creating a project.
---@field create_readme boolean Generate README.md for new projects.
---@field create_gitignore boolean Generate .gitignore for new projects.
---@field create_credits boolean Generate CREDITS.md for new projects.
---@field create_default_directories boolean Create the layout's default directories.
---@field remember_last_language boolean Remember the previously selected language.
---@field remember_last_manager boolean Remember the previously selected manager.
---@field default_keymaps boolean Register the minimal <leader>++ workspace mapping.
---@field legacy_shortcuts boolean Install the optional global shortcut set from HyperMax 0.6.0.

---@class (partial) HyperMax.ConfigOverrides : HyperMax.Config

---@class HyperMax.ConfigField
---@field type string
---@field allow_empty? boolean
---@field validate? fun(value: any): boolean
---@field invalid_message? string

---@class HyperMax.ConfigValidationIssue
---@field source string
---@field field string
---@field message string

local Config = {}

---@type HyperMax.Config
Config.defaults = {
	project_dir = "~/Projects",
	create_missing_dir = true,
	open_after_create = true,

	default_language = "cpp",
	default_manager = "native",
	default_layout = "",
	last_project_path = "",

	favourite_languages = {
		"cpp",
		"c",
		"lua",
		"python",
		"rust",
	},

	remember_last_project = true,
	show_progress = true,
	show_command_output = true,
	confirm_before_create = true,
	create_readme = true,
	create_gitignore = true,
	create_credits = true,
	create_default_directories = true,
	remember_last_language = true,
	remember_last_manager = true,
	default_keymaps = true,
	legacy_shortcuts = false,
}

---@type HyperMax.Config
Config.options = vim.deepcopy(Config.defaults)

---@type boolean
Config.configured = false

---@type HyperMax.ConfigValidationIssue[]
Config.issues = {}

---@type table<string, HyperMax.ConfigField>
local FIELD_SCHEMA = {
	project_dir = { type = "string" },
	create_missing_dir = { type = "boolean" },
	open_after_create = { type = "boolean" },
	default_language = { type = "string" },
	default_manager = { type = "string" },
	default_layout = { type = "string", allow_empty = true },
	last_project_path = { type = "string", allow_empty = true },
	favourite_languages = {
		type = "table",
		invalid_message = "expected a dense array of non-empty language IDs",
		validate = function(value)
			local count = 0
			local highest_index = 0
			for key, item in pairs(value) do
				if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
					return false
				end
				if type(item) ~= "string" or item:match("^%s*$") then
					return false
				end
				count = count + 1
				if key > highest_index then
					highest_index = key
				end
			end
			return highest_index == count
		end,
	},
	remember_last_project = { type = "boolean" },
	show_progress = { type = "boolean" },
	show_command_output = { type = "boolean" },
	confirm_before_create = { type = "boolean" },
	create_readme = { type = "boolean" },
	create_gitignore = { type = "boolean" },
	create_credits = { type = "boolean" },
	create_default_directories = { type = "boolean" },
	remember_last_language = { type = "boolean" },
	remember_last_manager = { type = "boolean" },
	default_keymaps = { type = "boolean" },
	legacy_shortcuts = { type = "boolean" },
}

local function Notify(message, level)
	if type(vim.notify) == "function" then
		vim.notify("HyperMax: " .. message, level or vim.log.levels.WARN)
	end
end

local function Settings_Path()
	return vim.fn.stdpath("data") .. "/hypermax/settings.json"
end

---@return table<string, any> settings
---@return HyperMax.ConfigValidationIssue|nil issue
local function Read_Settings()
	local path = Settings_Path()

	if vim.fn.filereadable(path) ~= 1 then
		return {}, nil
	end

	local read_ok, lines = pcall(vim.fn.readfile, path)
	if not read_ok then
		return {}, {
			source = "saved settings",
			field = path,
			message = "could not read settings file: " .. tostring(lines),
		}
	end

	local decode_ok, data = pcall(vim.json.decode, table.concat(lines, "\n"))
	if not decode_ok or type(data) ~= "table" then
		return {}, {
			source = "saved settings",
			field = path,
			message = "invalid JSON settings file; defaults will be used: " .. tostring(data),
		}
	end

	return data, nil
end

---@param value any
---@param spec HyperMax.ConfigField
---@return boolean
local function Is_Valid_Value(value, spec)
	if type(value) ~= spec.type then
		return false
	end

	if spec.type == "string" then
		if spec.allow_empty ~= true and value:match("^%s*$") then
			return false
		end
	elseif spec.validate and not spec.validate(value) then
		return false
	end

	-- Use Neovim's validator for scalar types as an additional API-level
	-- check. The custom checks above handle constraints vim.validate cannot
	-- express, such as the contents of favourite_languages.
	if spec.type ~= "table" then
		local ok = pcall(vim.validate, "value", value, spec.type)
		return ok
	end

	return true
end

local function Invalid_Value_Message(value, spec)
	if type(value) ~= spec.type then
		return "expected " .. spec.type .. ", got " .. type(value)
	end
	if spec.invalid_message then
		return spec.invalid_message
	end
	if spec.type == "string" then
		return "expected a non-empty string"
	end
	return "value did not pass validation"
end

---@param options any
---@param source string
---@return table<string, any> accepted
---@return HyperMax.ConfigValidationIssue[] issues
local function Filter_Options(options, source)
	local accepted = {}
	local issues = {}

	if options == nil then
		return accepted, issues
	end

	if type(options) ~= "table" then
		issues[#issues + 1] = {
			source = source,
			field = source,
			message = "expected a table, got " .. type(options),
		}
		return accepted, issues
	end

	for key, value in pairs(options) do
		local spec = FIELD_SCHEMA[key]
		if not spec then
			issues[#issues + 1] = {
				source = source,
				field = tostring(key),
				message = "unknown configuration field (ignored)",
			}
		elseif not Is_Valid_Value(value, spec) then
			issues[#issues + 1] = {
				source = source,
				field = key,
				message = Invalid_Value_Message(value, spec) .. " (the previous valid value was retained)",
			}
		else
			accepted[key] = vim.deepcopy(value)
		end
	end

	return accepted, issues
end

---@param options any
---@return boolean is_valid
---@return HyperMax.ConfigValidationIssue[] issues
function Config.validate(options)
	local _, issues = Filter_Options(options, "options")
	return #issues == 0, issues
end

---@return any options
---@return HyperMax.ConfigValidationIssue|nil issue
local function Read_Vim_Options()
	local options = vim.g.hypermax

	if type(options) == "function" then
		local ok, result = pcall(options)
		if not ok then
			return {}, {
				source = "vim.g.hypermax",
				field = "function",
				message = "configuration function failed: " .. tostring(result),
			}
		end
		options = result
	end

	return options, nil
end

local function Report_Issues(issues)
	for _, issue in ipairs(issues) do
		Notify(tostring(issue.source or "Configuration") .. "." .. issue.field .. ": " .. issue.message)
	end
end

---@param options? HyperMax.ConfigOverrides
---@return HyperMax.Config
function Config.setup(options)
	local saved_values, saved_read_issue = Read_Settings()
	local vim_values, vim_read_issue = Read_Vim_Options()
	local saved, saved_issues = Filter_Options(saved_values, "saved settings")
	local vim_options, vim_issues = Filter_Options(vim_values, "vim.g.hypermax")
	local explicit, explicit_issues = Filter_Options(options, "setup options")

	Config.issues = {}
	if saved_read_issue then Config.issues[#Config.issues + 1] = saved_read_issue end
	if vim_read_issue then Config.issues[#Config.issues + 1] = vim_read_issue end
	vim.list_extend(Config.issues, saved_issues)
	vim.list_extend(Config.issues, vim_issues)
	vim.list_extend(Config.issues, explicit_issues)
	Report_Issues(Config.issues)

	Config.options = vim.tbl_deep_extend(
		"force",
		{},
		vim.deepcopy(Config.defaults),
		saved,
		vim_options,
		explicit
	)

	-- Expand paths only after validation and merging.
	Config.options.project_dir = vim.fn.expand(Config.options.project_dir)
	Config.configured = true

	return Config.options
end

---Ensure defaults and persisted preferences are available when the runtime
---entry point initializes the plugin or when its public API is used directly.
---@return HyperMax.Config
function Config.initialize()
	if not Config.configured then
		return Config.setup()
	end
	return Config.options
end

---@param key string
---@return any
function Config.get(key)
	Config.initialize()
	return Config.options[key]
end

---@param key string
---@param value any
---@return boolean success
---@return string|nil error_message
function Config.set(key, value)
	Config.initialize()
	local spec = FIELD_SCHEMA[key]
	if not spec then
		return false, "Unknown configuration field: " .. tostring(key)
	end
	if not Is_Valid_Value(value, spec) then
		return false, "Invalid value for configuration field '" .. key .. "'"
	end

	Config.options[key] = vim.deepcopy(value)
	return Config.save()
end

---@return boolean success
---@return string|nil error_message
function Config.save()
	Config.initialize()
	local path = Settings_Path()
	local directory = vim.fn.fnamemodify(path, ":h")
	local mkdir_result = vim.fn.mkdir(directory, "p")
	if mkdir_result == 0 and vim.fn.isdirectory(directory) ~= 1 then
		return false, "Could not create settings directory: " .. directory
	end

	local ok, encoded = pcall(vim.json.encode, Config.options)
	if not ok then
		return false, "Could not encode settings: " .. tostring(encoded)
	end

	local file, err = io.open(path, "w")
	if not file then
		return false, "Could not save settings: " .. tostring(err)
	end

	local wrote, write_error = file:write(encoded, "\n")
	local closed, close_error = file:close()
	if not wrote or closed == nil then
		return false, "Could not finish saving settings: " .. tostring(write_error or close_error)
	end

	return true
end

---@return boolean success
---@return string|nil error_message
function Config.reset()
	Config.options = vim.deepcopy(Config.defaults)
	Config.options.project_dir = vim.fn.expand(Config.options.project_dir)
	Config.issues = {}
	Config.configured = true
	return Config.save()
end

---@return string
function Config.get_settings_path()
	return Settings_Path()
end

---@return table<string, HyperMax.ConfigField>
function Config.get_schema()
	return vim.deepcopy(FIELD_SCHEMA)
end

return Config
