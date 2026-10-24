local Project_Config = {}

local uv = vim.uv or vim.loop

local DATA_VERSION = 1
local HISTORY_HEADER = "HMXHIST\0" .. string.char(0, 0, 0, DATA_VERSION)

local IGNORED_DIRECTORIES = {
	[".git"] = true,
	[".hmc"] = true,
	["node_modules"] = true,
	["vendor"] = true,
	["target"] = true,
	["build"] = true,
	[".venv"] = true,
	["venv"] = true,
}

local MAX_LAYOUT_FILE_SIZE = 1024 * 1024

-- =========================================================
-- PATHS
-- =========================================================

local function Join(...)
	return table.concat({ ... }, "/"):gsub("/+", "/")
end

local function Get_Global_Directory()
	return Join(vim.fn.stdpath("data"), "hypermax")
end

local function Get_Global_Config_Path()
	return Join(Get_Global_Directory(), "config.json")
end

local function Get_HMC_Directory(project_root)
	return Join(project_root, ".hmc")
end

local function Get_HMC_Paths(project_root)
	local directory = Get_HMC_Directory(project_root)

	return {
		directory = directory,
		layout = Join(directory, "layout.json"),
		config = Join(directory, "config.json"),
		basics = Join(directory, "basics.json"),
		history = Join(directory, "project.bin"),
	}
end

-- =========================================================
-- FILESYSTEM
-- =========================================================

local function Ensure_Directory(path)
	if vim.fn.isdirectory(path) == 1 then
		return true
	end

	local result = vim.fn.mkdir(path, "p")

	if result == 0 and vim.fn.isdirectory(path) ~= 1 then
		return false, "Could not create directory: " .. path
	end

	return true
end

local function Read_File(path)
	local file = io.open(path, "rb")

	if not file then
		return nil
	end

	local content = file:read("*a")
	file:close()

	return content
end

local function Write_File(path, content)
	local file, err = io.open(path, "wb")

	if not file then
		return false, err
	end

	local ok, write_err = file:write(content)

	if not ok then
		file:close()
		return false, write_err
	end

	local closed, close_err = file:close()

	if closed == nil then
		return false, close_err
	end

	return true
end

local function Read_JSON(path, fallback)
	local content = Read_File(path)

	if not content or content == "" then
		return vim.deepcopy(fallback)
	end

	local ok, data = pcall(vim.json.decode, content)

	if not ok or type(data) ~= "table" then
		return nil, "Invalid JSON: " .. path
	end

	return data
end

local function Write_JSON(path, data)
	local ok, encoded = pcall(vim.json.encode, data)

	if not ok then
		return false, encoded
	end

	return Write_File(path, encoded .. "\n")
end

-- =========================================================
-- DIRECTORY CAPTURE
-- =========================================================

local function Capture_Directory(project_root)
	local entries = {}
	local errors = {}

	local function Scan(directory, relative)
		local handle, err = uv.fs_scandir(directory)

		if not handle then
			errors[#errors + 1] = tostring(err)
			return
		end

		while true do
			local name, kind = uv.fs_scandir_next(handle)

			if not name then
				break
			end

			if not (kind == "directory" and IGNORED_DIRECTORIES[name]) then
				local relative_path = relative == "" and name or relative .. "/" .. name

				local full_path = Join(directory, name)

				if kind == "directory" then
					entries[#entries + 1] = {
						path = relative_path,
						type = "directory",
					}

					Scan(full_path, relative_path)
				elseif kind == "file" then
					local stat = uv.fs_stat(full_path)

					local entry = {
						path = relative_path,
						type = "file",
						content_saved = false,
					}

					if stat and stat.size <= MAX_LAYOUT_FILE_SIZE then
						local content = Read_File(full_path)

						-- Avoid saving likely binary files as text.
						if content and not content:find("\0", 1, true) then
							entry.content = content
							entry.content_saved = true
						end
					end

					entries[#entries + 1] = entry
				end
			end
		end
	end

	Scan(project_root, "")

	table.sort(entries, function(a, b)
		return a.path < b.path
	end)

	return {
		version = DATA_VERSION,
		entries = entries,
		capture_errors = errors,
		captured_at = os.time(),
	}
end

-- =========================================================
-- DEFAULT CONFIGURATIONS
-- =========================================================

local function Default_Project_Config()
	return {
		version = DATA_VERSION,
		settings = {},
	}
end

local function Default_Basics(metadata)
	local project_name = metadata.name or vim.fs.basename(metadata.root)
	local git_directory = metadata.root .. "/.git"
	local git_enabled = vim.fn.isdirectory(git_directory) == 1

	return {
		version = DATA_VERSION,
		project = {
			name = project_name,
			root = metadata.root,
			language = metadata.language or "unknown",
			manager = metadata.manager or "native",
			creator = metadata.creator or os.getenv("USER") or "unknown",
			created_at = os.time(),
			entry_point = {
				file = metadata.entry_file or "",
				["function"] = metadata.entry_function or "main",
			},
		},
		git = {
			enabled = git_enabled,
		},
		conversion = metadata.conversion and {
			kind = metadata.conversion.kind or "folder_conversion",
			created_by = "hypermax",
			created_at = os.time(),
		} or nil,
	}
end

local function Default_Global_Config()
	return {
		version = DATA_VERSION,
		preferred_language = "c",
		base_location = Join(vim.fn.expand("~"), "Code"),
		preferred_manager = "native",
		settings = {},
	}
end

-- =========================================================
-- PUBLIC PATH AND EXISTENCE FUNCTIONS
-- =========================================================

function Project_Config.Get_Paths(project_root)
	project_root = vim.fn.fnamemodify(project_root, ":p")
	return Get_HMC_Paths(project_root)
end

-- Checks whether the project's .hmc directory exists.
function Project_Config.Exists(project_root)
	project_root = vim.fn.fnamemodify(project_root, ":p")

	local hmc_directory = Get_HMC_Directory(project_root)

	return vim.fn.isdirectory(hmc_directory) == 1
end

-- =========================================================
-- GLOBAL CONFIGURATION
-- =========================================================

function Project_Config.Get_Global()
	local path = Get_Global_Config_Path()
	local parent = Get_Global_Directory()

	local ok, err = Ensure_Directory(parent)

	if not ok then
		return nil, err
	end

	if vim.fn.filereadable(path) == 0 then
		local saved, save_err = Write_JSON(path, Default_Global_Config())

		if not saved then
			return nil, save_err
		end
	end

	return Read_JSON(path, Default_Global_Config())
end

function Project_Config.Save_Global(data)
	local ok, err = Ensure_Directory(Get_Global_Directory())

	if not ok then
		return false, err
	end

	data.version = DATA_VERSION

	return Write_JSON(Get_Global_Config_Path(), data)
end

-- =========================================================
-- CREATE PROJECT CONFIGURATION
-- =========================================================

function Project_Config.Create(project_root, metadata)
	project_root = vim.fn.fnamemodify(project_root, ":p")
	metadata = vim.deepcopy(metadata or {})
	metadata.root = project_root

	local paths = Get_HMC_Paths(project_root)

	if vim.fn.isdirectory(project_root) ~= 1 then
		return false, "Project directory does not exist: " .. project_root
	end

	if Project_Config.Exists(project_root) then
		return false, "This project already has a .hmc directory"
	end

	local ok, err = Ensure_Directory(paths.directory)

	if not ok then
		return false, err
	end

	local files = {
		{
			path = paths.basics,
			data = Default_Basics(metadata),
		},
		{
			path = paths.config,
			data = Default_Project_Config(),
		},
		{
			path = paths.layout,
			data = Capture_Directory(project_root),
		},
	}

	for _, item in ipairs(files) do
		local saved, save_err = Write_JSON(item.path, item.data)

		if not saved then
			pcall(vim.fn.delete, paths.directory, "rf")
			return false, save_err
		end
	end

	local history_saved, history_err = Write_File(paths.history, HISTORY_HEADER)

	if not history_saved then
		pcall(vim.fn.delete, paths.directory, "rf")
		return false, history_err
	end

	return true, paths
end

-- =========================================================
-- LOAD PROJECT CONFIGURATION
-- =========================================================

local function Read_Legacy_Basics(paths)
	local candidates = {
		paths.basics,
		Join(paths.directory, "basic.json"),
		Join(paths.directory, "project.json"),
		Join(paths.directory, "metadata.json"),
		Join(paths.directory, "project_config.json"),
		Join(paths.directory, "hypermax.json"),
	}
	local empty_data
	for _, path in ipairs(candidates) do
		if vim.fn.filereadable(path) == 1 then
			local data, err = Read_JSON(path, {})
			if not data then return nil, err end
			if type(data.project) ~= "table" or next(data.project) == nil then
				local project_keys = { "name", "root", "language", "manager", "creator", "created_at", "entry_file", "entry_function", "entry_point", "project_name", "project_root" }
				local project = {}
				for _, key in ipairs(project_keys) do
					if data[key] ~= nil then project[key] = data[key] end
				end
				project.name = project.name or data.project_name
				project.root = project.root or data.project_root
				if next(project) then data.project = project end
			end
			if type(data.project) == "table" and next(data.project) then
				data.project.entry_point = data.project.entry_point or {
					file = data.project.entry_file or data.entry_file or "",
					["function"] = data.project.entry_function or data.entry_function or "main",
				}
				data.git = data.git or { enabled = vim.fn.isdirectory(vim.fn.fnamemodify(paths.directory, ":h") .. "/.git") == 1 }
				return data
			end
			empty_data = data
		end
	end
	return empty_data or {}, nil
end

local function Read_Legacy_Config(paths)
	if vim.fn.filereadable(paths.config) == 1 then
		return Read_JSON(paths.config, Default_Project_Config())
	end
	for _, path in ipairs({ Join(paths.directory, "settings.json"), Join(paths.directory, "options.json") }) do
		if vim.fn.filereadable(path) == 1 then
			local data, err = Read_JSON(path, Default_Project_Config())
			if not data then return nil, err end
			if type(data.settings) ~= "table" then data = { version = data.version or DATA_VERSION, settings = data } end
			return data
		end
	end
	return Default_Project_Config(), nil
end

local function Read_Legacy_Layout(paths)
	local candidates = { paths.layout, Join(paths.directory, "tree.json"), Join(paths.directory, "files.json"), Join(paths.directory, "project_layout.json") }
	for _, path in ipairs(candidates) do
		if vim.fn.filereadable(path) == 1 then
			local data, err = Read_JSON(path, { version = DATA_VERSION, entries = {} })
			if not data then return nil, err end
			if type(data.entries) ~= "table" and type(data.files) == "table" then data.entries = data.files end
			data.entries = data.entries or {}
			data.version = data.version or DATA_VERSION
			return data
		end
	end
	return { version = DATA_VERSION, entries = {} }, nil
end

function Project_Config.Load(project_root)
	project_root = vim.fn.fnamemodify(project_root, ":p")

	local paths = Get_HMC_Paths(project_root)

	if not Project_Config.Exists(project_root) then
		return nil, "No .hmc directory exists in this project"
	end

	local basics, basics_err = Read_Legacy_Basics(paths)
	local config, config_err = Read_Legacy_Config(paths)
	local layout, layout_err = Read_Legacy_Layout(paths)

	if not basics then
		return nil, basics_err
	end

	if not config then
		return nil, config_err
	end

	if not layout then
		return nil, layout_err
	end

	return {
		root = project_root,
		paths = paths,
		basics = basics,
		config = config,
		layout = layout,
	}
end

-- =========================================================
-- PROJECT CONVERSION / SCRAPING
-- =========================================================

function Project_Config.Convert_Folder(project_root, metadata)
	project_root = vim.fn.fnamemodify(vim.fn.expand(project_root or ""), ":p")
	if project_root == "" or vim.fn.isdirectory(project_root) ~= 1 then
		return false, "Choose an existing folder to convert"
	end
	if Project_Config.Exists(project_root) then return false, "Folder is already a HyperMax project" end
	metadata = vim.deepcopy(metadata or {})
	metadata.name = metadata.name or vim.fs.basename(project_root)
	metadata.language = metadata.language or "unknown"
	metadata.manager = metadata.manager or "native"
	metadata.entry_file = metadata.entry_file or ""
	metadata.entry_function = metadata.entry_function or "main"
	metadata.conversion = { kind = "folder_conversion" }
	return Project_Config.Create(project_root, metadata)
end

local function Remove_HMC(project_root, require_conversion)
	project_root = vim.fn.fnamemodify(vim.fn.expand(project_root or ""), ":p")
	local loaded, err = Project_Config.Load(project_root)
	if not loaded then return false, err end
	if require_conversion and not (loaded.basics.conversion and loaded.basics.conversion.kind == "folder_conversion") then
		return false, "This project was not created by folder conversion; refusing to undo it"
	end
	local directory = loaded.paths.directory
	local stat = uv.fs_lstat(directory)
	if not stat or stat.type ~= "directory" then return false, "The .hmc metadata path is not a real directory" end
	local backup = directory .. ".backup-" .. os.date("%Y%m%d-%H%M%S")
	local renamed, rename_err = uv.fs_rename(directory, backup)
	if not renamed then return false, "Could not safely back up .hmc: " .. tostring(rename_err) end
	return true, backup
end

function Project_Config.Undo_Conversion(project_root)
	return Remove_HMC(project_root, true)
end

function Project_Config.Scrape(project_root)
	return Remove_HMC(project_root, false)
end

-- =========================================================
-- PROJECT SETTINGS
-- =========================================================

function Project_Config.Save_Project_Settings(project_root, settings)
	local paths = Get_HMC_Paths(vim.fn.fnamemodify(project_root, ":p"))

	if not Project_Config.Exists(project_root) then
		return false, "This project has no .hmc directory"
	end

	local config, err = Read_JSON(paths.config, Default_Project_Config())

	if not config then
		return false, err
	end

	config.settings = config.settings or {}

	for key, value in pairs(settings) do
		config.settings[key] = value
	end

	return Write_JSON(paths.config, config)
end

function Project_Config.Save_Setting(project_root, key, value)
	vim.ui.select({
		"This project only",
		"Global HyperMax defaults",
		"Cancel",
	}, {
		prompt = "Where should this setting be saved?",
	}, function(choice)
		if choice == "This project only" then
			local ok, err = Project_Config.Save_Project_Settings(project_root, { [key] = value })

			if not ok then
				vim.notify("HyperMax: " .. tostring(err), vim.log.levels.ERROR)
				return
			end

			vim.notify("Saved to project configuration")
		elseif choice == "Global HyperMax defaults" then
			local global, err = Project_Config.Get_Global()

			if not global then
				vim.notify("HyperMax: " .. tostring(err), vim.log.levels.ERROR)
				return
			end

			global.settings = global.settings or {}
			global.settings[key] = value

			local ok, save_err = Project_Config.Save_Global(global)

			if not ok then
				vim.notify("HyperMax: " .. tostring(save_err), vim.log.levels.ERROR)
				return
			end

			vim.notify("Saved to global HyperMax configuration")
		end
	end)
end

return Project_Config
