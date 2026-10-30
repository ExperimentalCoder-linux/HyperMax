local Project_Config = {}

local uv = vim.uv or vim.loop
Project_Config.global_path = nil

local DATA_VERSION = 1
local HISTORY_HEADER = "HMXHIST\0" .. string.char(0, 0, 0, DATA_VERSION)

-- These settings belong to one project and are stored in .hmc/config.json.
-- Global project-generation defaults remain in the user's Neovim data folder.
local DEFAULT_PROJECT_SETTINGS = {
	entry_point = {
		["function"] = "main",
	},
	show_hidden = true,
	exclude_paths = {},
	show_tabs = true,
	context_position = "center",
	pinned_tasks_position = "top",
	auto_save_after_success = true,
}

local IGNORED_DIRECTORIES = {
	[".git"] = true,
	[".hmc"] = true,
	["node_modules"] = true,
	["vendor"] = true,
	["target"] = true,
	["build"] = true,
	[".venv"] = true,
	["venv"] = true,
	["dist"] = true,
	["__pycache__"] = true,
	[".pytest_cache"] = true,
	[".mypy_cache"] = true,
	[".ruff_cache"] = true,
	[".next"] = true,
	[".turbo"] = true,
	[".ssh"] = true,
	[".aws"] = true,
	[".gnupg"] = true,
}

local MAX_LAYOUT_FILE_SIZE = 4 * 1024 * 1024

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

	local function Is_Sensitive_File(name)
		local lower = name:lower()
		if lower == ".env.example" or lower == ".env.sample" or lower == ".env.template" then return false end
		if lower == ".env" or lower:match("^%.env%.") then return true end
		if lower == ".npmrc" or lower == ".pypirc" or lower == ".netrc" then return true end
		return lower == "id_rsa" or lower == "id_ed25519" or lower:match("%.pem$") ~= nil
			or lower:match("%.p12$") ~= nil or lower:match("%.pfx$") ~= nil or lower:match("%.key$") ~= nil
	end

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

			local metadata_path = name == ".git" or name == ".hmc" or name:match("^%.hmc%.backup%-") ~= nil
			if not metadata_path and not (kind == "directory" and IGNORED_DIRECTORIES[name]) then
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

					if Is_Sensitive_File(name) then
						entry.skip_reason = "Potential secret or credential file"
					elseif not stat then
						entry.skip_reason = "Could not inspect file"
					elseif stat.size > MAX_LAYOUT_FILE_SIZE then
						entry.skip_reason = "File exceeds 4 MiB capture limit"
					else
						local content = Read_File(full_path)
						-- Avoid saving likely binary files as text.
						if content and not content:find("\0", 1, true) then
							entry.content = content
							entry.content_saved = true
						else
							entry.skip_reason = "Binary or unreadable file"
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
		settings = vim.deepcopy(DEFAULT_PROJECT_SETTINGS),
	}
end

local function Default_Basics(metadata)
	local project_name = metadata.name or vim.fs.basename(metadata.root)
	local git_marker = metadata.root .. "/.git"
	-- Git worktrees and submodules may use a .git *file*, not a directory.
	local git_enabled = vim.fn.isdirectory(git_marker) == 1 or vim.fn.filereadable(git_marker) == 1

	return {
		version = DATA_VERSION,
		project = {
			id = metadata.id or (vim.fn.sha256(metadata.root .. "|" .. tostring(os.time())):sub(1, 16)),
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
		projects = {},
		last_project = "",
		last_open_order = 0,
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
	local path = Project_Config.global_path or Get_Global_Config_Path()
	local parent = vim.fn.fnamemodify(path, ":h")

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

	local data, read_err = Read_JSON(path, Default_Global_Config())

	if not data then
		return nil, read_err
	end

	data.projects = type(data.projects) == "table" and data.projects or {}
	data.last_project = type(data.last_project) == "string" and data.last_project or ""
	data.settings = type(data.settings) == "table" and data.settings or {}
	local last_open_order = tonumber(data.last_open_order) or 0
	for _, entry in ipairs(data.projects) do
		if type(entry) == "table" then
			last_open_order = math.max(last_open_order, tonumber(entry.last_open_order) or 0)
		end
	end
	data.last_open_order = last_open_order

	return data
end

function Project_Config.Save_Global(data)
	local path = Project_Config.global_path or Get_Global_Config_Path()
	local ok, err = Ensure_Directory(vim.fn.fnamemodify(path, ":h"))

	if not ok then
		return false, err
	end

	data.version = DATA_VERSION
	data.projects = type(data.projects) == "table" and data.projects or {}
	data.last_project = type(data.last_project) == "string" and data.last_project or ""
	data.settings = type(data.settings) == "table" and data.settings or {}
	data.last_open_order = tonumber(data.last_open_order) or 0

	return Write_JSON(path, data)
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

	-- Project metadata is the durable project marker; the global index makes
	-- converted folders discoverable even when they are outside project_dir.
	local registered, register_error = Project_Config.Register_Project(project_root)
	if not registered then
		vim.notify("HyperMax: Project was created, but could not update the project index: " .. tostring(register_error), vim.log.levels.WARN)
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
				local git_marker = vim.fn.fnamemodify(paths.directory, ":h") .. "/.git"
				data.git = data.git or { enabled = vim.fn.isdirectory(git_marker) == 1 or vim.fn.filereadable(git_marker) == 1 }
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

-- Return the effective per-project settings, filling keys missing from older
-- .hmc/config.json files with defaults without mutating the stored file.
function Project_Config.Get_Project_Settings(project_root)
	project_root = vim.fn.fnamemodify(project_root, ":p")
	if not Project_Config.Exists(project_root) then
		return nil, "No .hmc directory exists in this project"
	end
	local saved_config, err = Read_Legacy_Config(Get_HMC_Paths(project_root))
	if not saved_config then return nil, err end
	local saved = type(saved_config.settings) == "table" and saved_config.settings or {}
	return vim.tbl_deep_extend("force", vim.deepcopy(DEFAULT_PROJECT_SETTINGS), saved)
end

-- =========================================================
-- GLOBAL PROJECT REGISTRY
-- =========================================================

local function Normalize_Project_Root(project_root)
	if type(project_root) ~= "string" or project_root == "" then
		return nil
	end

	local normalized = vim.fn.fnamemodify(vim.fn.expand(project_root), ":p")
	if normalized ~= "/" then
		normalized = normalized:gsub("/+$", "")
	end
	return normalized
end

function Project_Config.Register_Project(project_root, metadata)
	project_root = Normalize_Project_Root(project_root)
	if not project_root or not Project_Config.Exists(project_root) then
		return false, "Cannot register a folder without a .hmc project marker"
	end

	local loaded, load_error = Project_Config.Load(project_root)
	if not loaded then
		return false, load_error
	end

	local project = (loaded.basics and loaded.basics.project) or {}
	metadata = vim.deepcopy(metadata or {})
	local global, global_error = Project_Config.Get_Global()
	if not global then
		return false, global_error
	end

	local now = os.time()
	local latest_order = tonumber(global.last_open_order) or 0
	for _, item in ipairs(global.projects or {}) do
		if type(item) == "table" then
			latest_order = math.max(latest_order, tonumber(item.last_open_order) or 0)
		end
	end
	-- A durable sequence number gives strict recency ordering even when several
	-- projects are opened in the same second or the system clock moves backward.
	local next_open_order = latest_order + 1
	local entry = nil
	local projects = {}
	for _, item in ipairs(global.projects or {}) do
		if type(item) == "table" then
			local item_path = Normalize_Project_Root(item.path or item.root)
			if item_path == project_root then
				entry = item
			elseif item_path then
				projects[#projects + 1] = item
			end
		end
	end

	entry = entry or { added_at = now }
	entry.id = project.id or entry.id or vim.fn.sha256(project_root):sub(1, 16)
	entry.name = metadata.name or project.name or vim.fs.basename(project_root)
	entry.path = project_root
	entry.language = metadata.language or project.language or "unknown"
	entry.manager = metadata.manager or project.manager or "native"
	entry.created_at = project.created_at or entry.created_at or now
	entry.last_opened = now
	entry.last_open_order = next_open_order
	projects[#projects + 1] = entry

	table.sort(projects, function(a, b)
		return (a.name or a.path or ""):lower() < (b.name or b.path or ""):lower()
	end)

	global.projects = projects
	global.last_project = project_root
	global.last_open_order = next_open_order
	return Project_Config.Save_Global(global)
end

function Project_Config.Mark_Project_Opened(project_root)
	return Project_Config.Register_Project(project_root)
end

function Project_Config.Unregister_Project(project_root)
	project_root = Normalize_Project_Root(project_root)
	if not project_root then return false, "Project root is not a valid path" end
	local global, err = Project_Config.Get_Global()
	if not global then return false, err end
	local projects = {}
	for _, entry in ipairs(global.projects or {}) do
		if type(entry) == "table" and Normalize_Project_Root(entry.path or entry.root) ~= project_root then
			projects[#projects + 1] = entry
		end
	end
	global.projects = projects
	if Normalize_Project_Root(global.last_project) == project_root then global.last_project = "" end
	return Project_Config.Save_Global(global)
end

function Project_Config.Get_Last_Project()
	local global, err = Project_Config.Get_Global()
	if not global then return nil, err end
	local path = Normalize_Project_Root(global.last_project)
	if path and Project_Config.Exists(path) then return path end

	local latest
	for _, entry in ipairs(global.projects or {}) do
		if type(entry) == "table" and Project_Config.Exists(entry.path) then
			local entry_order = tonumber(entry.last_open_order) or 0
			local latest_order = latest and (tonumber(latest.last_open_order) or 0) or -1
			local entry_time = tonumber(entry.last_opened) or 0
			local latest_time = latest and (tonumber(latest.last_opened) or 0) or -1
			if not latest or entry_order > latest_order or (entry_order == latest_order and entry_time > latest_time) then
				latest = entry
			end
		end
	end
	return latest and latest.path or nil
end

function Project_Config.List_Projects(project_directory)
	local global, err = Project_Config.Get_Global()
	if not global then return nil, err end
	local found = {}

	local function Add(path, registry_entry)
		path = Normalize_Project_Root(path)
		if not path or found[path] or not Project_Config.Exists(path) then return end
		local loaded = Project_Config.Load(path)
		if not loaded then return end
		local project = (loaded.basics and loaded.basics.project) or {}
		found[path] = {
			id = project.id or vim.fn.sha256(path):sub(1, 16),
			name = project.name or vim.fs.basename(path),
			path = path,
			language = project.language or "unknown",
			manager = project.manager or "native",
			created_at = project.created_at,
			added_at = type(registry_entry) == "table" and registry_entry.added_at or nil,
			last_opened = type(registry_entry) == "table" and registry_entry.last_opened or nil,
			last_open_order = type(registry_entry) == "table" and registry_entry.last_open_order or nil,
		}
	end

	for _, entry in ipairs(global.projects or {}) do
		if type(entry) == "table" then Add(entry.path or entry.root, entry) end
	end

	-- Discover direct children as a recovery path for projects created before
	-- the index existed or copied from another machine.
	if type(project_directory) == "string" and project_directory ~= "" then
		local directory = vim.fn.expand(project_directory)
		local scan = uv.fs_scandir(directory)
		if scan then
			while true do
				local name, kind = uv.fs_scandir_next(scan)
				if not name then break end
				if kind == "directory" and name ~= "." and name ~= ".." then Add(Join(directory, name)) end
			end
		end
	end

	local projects = {}
	for _, entry in pairs(found) do projects[#projects + 1] = entry end
	local last_project = Normalize_Project_Root(global.last_project)
	table.sort(projects, function(a, b)
		-- The sequence is the durable ordering key. Wall-clock timestamps remain
		-- useful for display but can tie or move backward.
		local ao, bo = tonumber(a.last_open_order) or 0, tonumber(b.last_open_order) or 0
		if ao ~= bo then return ao > bo end
		local at, bt = tonumber(a.last_opened) or 0, tonumber(b.last_opened) or 0
		if at ~= bt then return at > bt end
		local a_is_last, b_is_last = a.path == last_project, b.path == last_project
		if a_is_last ~= b_is_last then return a_is_last end
		local an, bn = (a.name or ""):lower(), (b.name or ""):lower()
		if an ~= bn then return an < bn end
		return a.path < b.path
	end)
	return projects
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
	local unregistered, unregister_error = Project_Config.Unregister_Project(project_root)
	if not unregistered then
		vim.notify("HyperMax: Metadata was backed up, but the global project index could not be updated: " .. tostring(unregister_error), vim.log.levels.WARN)
	end
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
	if type(settings) ~= "table" then
		return false, "Project settings must be provided as a table"
	end

	local paths = Get_HMC_Paths(vim.fn.fnamemodify(project_root, ":p"))

	if not Project_Config.Exists(project_root) then
		return false, "This project has no .hmc directory"
	end

	local config, err = Read_JSON(paths.config, Default_Project_Config())

	if not config then
		return false, err
	end

	config.settings = vim.tbl_deep_extend(
		"force",
		vim.deepcopy(DEFAULT_PROJECT_SETTINGS),
		type(config.settings) == "table" and config.settings or {}
	)

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
