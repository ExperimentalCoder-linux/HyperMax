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

local function Join(...)
	return table.concat({ ... }, "/"):gsub("/+", "/")
end

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
					}

					if stat and stat.size <= MAX_LAYOUT_FILE_SIZE then
						local content = Read_File(full_path)

						if content then
							entry.content = content
							entry.content_saved = true
						end
					else
						entry.content_saved = false
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

local function Default_Project_Config()
	return {
		version = DATA_VERSION,
		settings = {},
	}
end

local function Default_Basics(metadata)
	return {
		version = DATA_VERSION,
		project = {
			name = metadata.name or vim.fs.basename(metadata.root),
			root = metadata.root,
			language = metadata.language or "unknown",
			manager = metadata.manager or "native",
			creator = metadata.creator or os.getenv("USER") or "unknown",
			created_at = os.time(),
		},
		git = {
			enabled = vim.fn.isdirectory(Join(metadata.root, ".git")) == 1,
		},
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

function Project_Config.Get_Paths(project_root)
	return Get_HMC_Paths(vim.fn.fnamemodify(project_root, ":p"))
end

function Project_Config.Exists(project_root)
	return vim.fn.isdirectory(Get_HMC_Directory(project_root)) == 1
end

function Project_Config.Create(project_root, metadata)
	project_root = vim.fn.fnamemodify(project_root, ":p")
	metadata = vim.deepcopy(metadata or {})
	metadata.root = project_root

	local paths = Get_HMC_Paths(project_root)

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
			return false, save_err
		end
	end

	local history_saved, history_err = Write_File(paths.history, HISTORY_HEADER)

	if not history_saved then
		return false, history_err
	end

	return true, paths
end

function Project_Config.Load(project_root)
	project_root = vim.fn.fnamemodify(project_root, ":p")

	local paths = Get_HMC_Paths(project_root)

	if not Project_Config.Exists(project_root) then
		return nil, "No .hmc directory exists in this project"
	end

	local basics, basics_err = Read_JSON(paths.basics, {})
	local config, config_err = Read_JSON(paths.config, Default_Project_Config())
	local layout, layout_err = Read_JSON(paths.layout, {
		version = DATA_VERSION,
		entries = {},
	})

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

function Project_Config.Save_Project_Settings(project_root, settings)
	local paths = Get_HMC_Paths(project_root)

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
