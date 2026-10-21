local Config = {}

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
}

Config.options = {}

local function Settings_Path()
	return vim.fn.stdpath("data") .. "/hypermax/settings.json"
end

local function Read_Settings()
	local path = Settings_Path()

	if vim.fn.filereadable(path) ~= 1 then
		return {}
	end

	local content = table.concat(vim.fn.readfile(path), "\n")
	local ok, data = pcall(vim.json.decode, content)

	if ok and type(data) == "table" then
		return data
	end

	vim.notify("HyperMax: Could not read settings JSON.", vim.log.levels.WARN)

	return {}
end

function Config.save()
	local path = Settings_Path()
	local directory = vim.fn.fnamemodify(path, ":h")

	vim.fn.mkdir(directory, "p")

	local ok, encoded = pcall(vim.json.encode, Config.options)

	if not ok then
		vim.notify("HyperMax: Could not encode settings.", vim.log.levels.ERROR)
		return false
	end

	local file, err = io.open(path, "w")

	if not file then
		vim.notify("HyperMax: Could not save settings: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end

	file:write(encoded, "\n")
	file:close()

	return true
end

function Config.setup(options)
	options = options or {}

	local saved = Read_Settings()

	Config.options = vim.tbl_deep_extend("force", {}, Config.defaults, saved, options)

	Config.options.project_dir = vim.fn.expand(Config.options.project_dir)

	return Config.options
end

function Config.get(key)
	return Config.options[key]
end

function Config.set(key, value)
	Config.options[key] = value
	return Config.save()
end

function Config.reset()
	Config.options = vim.deepcopy(Config.defaults)
	Config.options.project_dir = vim.fn.expand(Config.options.project_dir)

	return Config.save()
end

function Config.get_settings_path()
	return Settings_Path()
end

return Config
