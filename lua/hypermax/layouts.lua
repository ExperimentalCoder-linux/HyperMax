local Layouts = {}

local uv = vim.uv or vim.loop

local function Get_Module_Directory()
	local source = debug.getinfo(1, "S").source

	if source:sub(1, 1) ~= "@" then
		return vim.fn.getcwd()
	end

	return vim.fn.fnamemodify(source:sub(2), ":p:h")
end

Layouts.json_path = Get_Module_Directory() .. "/layouts.json"
Layouts.user_path = vim.fn.stdpath("data") .. "/hypermax/layouts.json"

-- =========================================================
-- FILESYSTEM
-- =========================================================

local function Is_Directory(path)
	local stat = uv.fs_stat(path)
	return stat ~= nil and stat.type == "directory"
end

local function Read_File(path)
	local file = io.open(path, "r")

	if not file then
		return nil
	end

	local content = file:read("*a")
	file:close()

	return content
end

local function Read_JSON(path)
	local content = Read_File(path)

	if not content then
		return nil, "Could not read JSON file: " .. path
	end

	local ok, decoded = pcall(vim.json.decode, content)

	if not ok or type(decoded) ~= "table" then
		return nil, "Invalid JSON in " .. path
	end

	return decoded
end

local function Write_JSON(path, data)
	local parent = vim.fn.fnamemodify(path, ":h")
	local mkdir_ok = vim.fn.mkdir(parent, "p")

	if mkdir_ok == 0 and not Is_Directory(parent) then
		return false, "Could not create directory: " .. parent
	end

	local ok, encoded = pcall(vim.json.encode, data)

	if not ok then
		return false, "Could not encode JSON: " .. tostring(encoded)
	end

	local file, err = io.open(path, "w")

	if not file then
		return false, err
	end

	local write_ok, write_err = file:write(vim.json.format and vim.json.format(encoded) or encoded, "\n")

	local close_ok, close_err = file:close()

	if not write_ok then
		return false, write_err
	end

	if close_ok == nil then
		return false, close_err
	end

	return true
end

local function Deep_Copy(value)
	return vim.deepcopy(value)
end

local function Merge(destination, source)
	return vim.tbl_deep_extend("force", destination or {}, source or {})
end

-- =========================================================
-- PATH VALIDATION
-- =========================================================

function Layouts.Is_Safe_Path(path)
	if type(path) ~= "string" or path == "" then
		return false
	end

	if path:find("[%c]") or path:find("\\") then
		return false
	end

	if path:sub(1, 1) == "/" or path:match("^%a:") then
		return false
	end

	for part in path:gmatch("[^/]+") do
		local lower = part:lower()
		if part == "." or part == ".." or lower == ".hmc" or lower == ".git" or lower == ".hg" or lower == ".svn" then
			return false
		end
	end

	return true
end

local function Validate_Files(files, label)
	if type(files) ~= "table" then
		return false, label .. ".files must be a table"
	end

	for path, content in pairs(files) do
		if not Layouts.Is_Safe_Path(path) then
			return false, "Unsafe file path: " .. tostring(path)
		end

		if type(content) ~= "string" then
			return false, "File contents must be strings: " .. path
		end
	end

	return true
end

local function Validate_Directories(directories, label)
	if type(directories) ~= "table" then
		return false, label .. ".directories must be a list"
	end

	local count, max_index = 0, 0
	for key in pairs(directories) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false, label .. ".directories must be a sequential list"
		end
		count = count + 1
		max_index = math.max(max_index, key)
	end
	if count ~= max_index then
		return false, label .. ".directories must not contain missing list entries"
	end

	for _, path in ipairs(directories) do
		if not Layouts.Is_Safe_Path(path) then
			return false, "Unsafe directory path: " .. tostring(path)
		end
	end

	return true
end

local function Validate_Layout(id, layout)
	if type(layout) ~= "table" then
		return false, "Layout must be a table: " .. tostring(id)
	end

	if layout.name ~= nil and type(layout.name) ~= "string" then
		return false, "Layout name must be a string: " .. id
	end

	if layout.description ~= nil and type(layout.description) ~= "string" then
		return false, "Layout description must be a string: " .. id
	end

	if layout.languages ~= nil then
		if type(layout.languages) ~= "table" then
			return false, "Layout languages must be a list: " .. id
		end

		for _, language_id in ipairs(layout.languages) do
			if type(language_id) ~= "string" then
				return false, "Invalid language ID in layout: " .. id
			end
		end
	end

	if layout.entry ~= nil then
		if not Layouts.Is_Safe_Path(layout.entry) then
			return false, "Unsafe layout entry path: " .. id
		end
	end

	if layout.directories ~= nil then
		local ok, err = Validate_Directories(layout.directories, id)

		if not ok then
			return false, err
		end
	end

	if layout.files ~= nil then
		local ok, err = Validate_Files(layout.files, id)

		if not ok then
			return false, err
		end
	end

	return true
end

-- =========================================================
-- LOAD CONFIGURATION
-- =========================================================

Layouts.data = {
	version = 1,
	defaults = {
		directories = {},
		files = {},
	},
	credits = {
		path = "CREDITS.md",
		content = "",
	},
	languages = {},
	layouts = {},
}

local function Load_Source(path)
	if vim.fn.filereadable(path) ~= 1 then
		return nil
	end

	local data, err = Read_JSON(path)

	if not data then
		return nil, err
	end

	if type(data.layouts) ~= "table" then
		return nil, "JSON must contain a 'layouts' object: " .. path
	end

	return data
end

function Layouts.Load_File(path)
	local data, err = Load_Source(path)

	if not data then
		return nil, err
	end

	for id, layout in pairs(data.layouts) do
		local ok, validation_error = Validate_Layout(id, layout)

		if not ok then
			return nil, validation_error
		end
	end

	return data
end

function Layouts.Reload()
	local base = {
		version = 1,
		defaults = {
			directories = {},
			files = {},
		},
		credits = {
			path = "CREDITS.md",
			content = "",
		},
		languages = {},
		layouts = {},
	}

	local developer_data, developer_error = Layouts.Load_File(Layouts.json_path)

	if developer_data then
		base.version = developer_data.version or 1
		base.defaults = Merge(base.defaults, developer_data.defaults)
		base.credits = Merge(base.credits, developer_data.credits)
		base.languages = Merge(base.languages, developer_data.languages)
		base.layouts = Merge(base.layouts, developer_data.layouts)
	elseif vim.fn.filereadable(Layouts.json_path) == 1 then
		return false, developer_error
	end

	-- User-defined layouts override developer layouts.
	local user_data, user_error = Layouts.Load_File(Layouts.user_path)

	if user_data then
		base.layouts = Merge(base.layouts, user_data.layouts)
	elseif vim.fn.filereadable(Layouts.user_path) == 1 then
		return false, user_error
	end

	for id, layout in pairs(base.layouts) do
		local ok, err = Validate_Layout(id, layout)

		if not ok then
			return false, err
		end
	end

	if type(base.defaults.directories) ~= "table" or type(base.defaults.files) ~= "table" then
		return false, "defaults must contain directories and files"
	end

	local ok, err = Validate_Directories(base.defaults.directories, "defaults")

	if not ok then
		return false, err
	end

	ok, err = Validate_Files(base.defaults.files, "defaults")

	if not ok then
		return false, err
	end

	if type(base.languages) ~= "table" then
		return false, "languages must be an object"
	end

	if
		type(base.credits) ~= "table"
		or type(base.credits.path) ~= "string"
		or type(base.credits.content) ~= "string"
		or not Layouts.Is_Safe_Path(base.credits.path)
	then
		return false, "Invalid credits configuration"
	end

	Layouts.data = base
	return true
end

-- Load the JSON when this module is first required.
local loaded, load_error = Layouts.Reload()

if not loaded then
	vim.schedule(function()
		vim.notify("HyperMax layouts: " .. tostring(load_error), vim.log.levels.ERROR, { title = "HyperMax" })
	end)
end

-- =========================================================
-- GENERAL GETTERS
-- =========================================================

function Layouts.Get_Config()
	return Layouts.data
end

function Layouts.Get_Defaults()
	return Deep_Copy(Layouts.data.defaults)
end

function Layouts.Get_Credits()
	return Deep_Copy(Layouts.data.credits)
end

function Layouts.Get_Language(language_id)
	return Deep_Copy(Layouts.data.languages[language_id] or {})
end

function Layouts.Get_Languages()
	return Deep_Copy(Layouts.data.languages)
end

function Layouts.Get_All()
	local layouts = Deep_Copy(Layouts.data.layouts)
	for id, layout in pairs(layouts) do
		layout.id = id
	end
	return layouts
end

function Layouts.Get(id)
	local layout = Layouts.data.layouts[id]

	if not layout then
		return nil
	end

	local copy = Deep_Copy(layout)
	copy.id = id
	return copy
end

function Layouts.Exists(id)
	return Layouts.data.layouts[id] ~= nil
end

function Layouts.Get_IDs()
	local ids = {}

	for id in pairs(Layouts.data.layouts) do
		ids[#ids + 1] = id
	end

	table.sort(ids)

	return ids
end

function Layouts.Get_For_Language(language_id)
	local ids = {}

	for id, layout in pairs(Layouts.data.layouts) do
		local allowed = layout.languages

		if allowed == nil then
			ids[#ids + 1] = id
		else
			for _, allowed_id in ipairs(allowed) do
				if allowed_id == language_id then
					ids[#ids + 1] = id
					break
				end
			end
		end
	end

	table.sort(ids)

	return ids
end

-- =========================================================
-- FILE CONTENT PLACEHOLDERS
-- =========================================================

local function Replace_Placeholders(content, values)
	for key, value in pairs(values or {}) do
		content = content:gsub("{{" .. key .. "}}", function()
			return tostring(value)
		end)
	end

	return content
end

function Layouts.Get_Commands(language_id, project_name)
	local language = Layouts.Get_Language(language_id)

	local values = {
		PROJECT_NAME = project_name or "MyProject",
		LANGUAGE = language_id,
		BUILD_COMMAND = language.build or "Not configured",
		RUN_COMMAND = language.run or "Not configured",
		TEST_COMMAND = language.test or "Not configured",
		CLEAN_COMMAND = language.clean or "Not configured",
	}

	for key, value in pairs(language) do
		if type(value) == "string" then
			values[key:upper()] = value
		end
	end

	return values
end

-- =========================================================
-- BUILD A PROJECT FILE MANIFEST
-- =========================================================

function Layouts.Build_Manifest(language_id, layout_id, project_name)
	local defaults = Layouts.data.defaults
	local language = Layouts.Get_Language(language_id)
	local layout = layout_id and layout_id ~= "" and Layouts.Get(layout_id) or nil

	if layout_id and layout_id ~= "" and not layout then
		return nil, "Unknown layout: " .. tostring(layout_id)
	end

	if layout and layout.languages then
		local supported = false

		for _, allowed_id in ipairs(layout.languages) do
			if allowed_id == language_id then
				supported = true
				break
			end
		end

		if not supported then
			return nil, "Layout '" .. layout_id .. "' does not support language '" .. language_id .. "'"
		end
	end

	local directories = {}
	local directory_set = {}
	local files = {}

	local function Add_Directory(path)
		if not Layouts.Is_Safe_Path(path) then
			error("Unsafe directory path: " .. tostring(path))
		end

		if not directory_set[path] then
			directory_set[path] = true
			directories[#directories + 1] = path
		end
	end

	local function Add_Directories(list)
		for _, path in ipairs(list or {}) do
			Add_Directory(path)
		end
	end

	local function Add_Files(source)
		for path, content in pairs(source or {}) do
			if not Layouts.Is_Safe_Path(path) then
				error("Unsafe file path: " .. tostring(path))
			end

			if type(content) ~= "string" then
				error("Invalid file content: " .. tostring(path))
			end

			files[path] = content
		end
	end

	local ok, err = pcall(function()
		-- 1. Common project structure.
		Add_Directories(defaults.directories)
		Add_Files(defaults.files)

		-- 2. Language-specific settings and optional files.
		Add_Directories(language.directories)
		Add_Files(language.files)

		-- 3. Universal credits file.
		files[Layouts.data.credits.path] = Layouts.data.credits.content

		-- 4. Selected specialized layout overrides defaults.
		if layout then
			Add_Directories(layout.directories)
			Add_Files(layout.files)
		end

		-- 5. Build a Makefile when language commands are configured.
		-- An explicit Makefile supplied by the layout takes precedence.
		if not files["Makefile"] and (language.build or language.run or language.test or language.clean) then
			local commands = Layouts.Get_Commands(language_id, project_name)

			local makefile = {
				".PHONY: all build run test clean",
				"",
			}

			if language.build then
				makefile[#makefile + 1] = "all: build"
				makefile[#makefile + 1] = ""
				makefile[#makefile + 1] = "build:"
				makefile[#makefile + 1] = "\t" .. language.build
				makefile[#makefile + 1] = ""
			else
				makefile[#makefile + 1] = "all:"
				makefile[#makefile + 1] = '\t@echo "No build command configured"'
				makefile[#makefile + 1] = ""
			end

			for _, target in ipairs({ "run", "test", "clean" }) do
				if language[target] then
					makefile[#makefile + 1] = target .. ":"
					makefile[#makefile + 1] = "\t" .. language[target]
					makefile[#makefile + 1] = ""
				end
			end

			files["Makefile"] = table.concat(makefile, "\n") .. "\n"
		end

		-- 6. Substitute documentation placeholders.
		local replacements = Layouts.Get_Commands(language_id, project_name)

		for path, content in pairs(files) do
			files[path] = Replace_Placeholders(content, replacements)
		end
	end)

	if not ok then
		return nil, tostring(err)
	end

	table.sort(directories)

	return {
		language = language_id,
		project_name = project_name or "MyProject",
		entry = layout and layout.entry or language.entry,
		directories = directories,
		files = files,
		commands = Layouts.Get_Commands(language_id, project_name),
		layout_id = layout_id,
	}
end

-- =========================================================
-- APPLY A PROJECT MANIFEST
-- =========================================================

local function Write_New_File(path, content)
	local parent = vim.fn.fnamemodify(path, ":h")

	local mkdir_ok = vim.fn.mkdir(parent, "p")

	if mkdir_ok == 0 and not Is_Directory(parent) then
		return false, "Could not create directory: " .. parent
	end

	-- Never overwrite an existing file.
	if uv.fs_lstat(path) then
		return false, "Refusing to overwrite existing path: " .. path
	end

	local file, err = io.open(path, "wx")

	if not file then
		-- Some Lua builds do not support exclusive creation mode.
		if err and err:find("invalid mode") then
			if uv.fs_lstat(path) then
				return false, "Refusing to overwrite existing path: " .. path
			end

			file, err = io.open(path, "w")
		end
	end

	if not file then
		return false, err
	end

	local write_ok, write_err = file:write(content)
	local close_ok, close_err = file:close()

	if not write_ok then
		return false, write_err
	end

	if close_ok == nil then
		return false, close_err
	end

	return true
end

function Layouts.Apply(root, layout, language_id, project_name)
	if type(root) ~= "string" or root == "" then
		return false, "Project root is required"
	end

	root = vim.fn.fnamemodify(root, ":p")

	if not Is_Directory(root) then
		return false, "Project root must already exist: " .. root
	end

	-- Backwards compatibility with Project.Create(root, layout).
	if type(layout) == "string" and language_id == nil then
		language_id = layout
		layout = nil
	end

	if type(layout) == "table" and layout.id then
		language_id = language_id or layout.language
	end

	local layout_id = nil

	if type(layout) == "string" then
		layout_id = layout
	elseif type(layout) == "table" then
		for id, registered in pairs(Layouts.data.layouts) do
			if registered == layout then
				layout_id = id
				break
			end
		end
	end

	language_id = language_id or "cpp"
	project_name = project_name or vim.fn.fnamemodify(root, ":t")

	local manifest, manifest_error = Layouts.Build_Manifest(language_id, layout_id, project_name)

	if not manifest then
		return false, manifest_error
	end

	-- Create directories first.
	for _, relative_path in ipairs(manifest.directories) do
		if not Layouts.Is_Safe_Path(relative_path) then
			return false, "Unsafe directory path: " .. relative_path
		end

		local full_path = root .. "/" .. relative_path
		local mkdir_ok = vim.fn.mkdir(full_path, "p")

		if mkdir_ok == 0 and not Is_Directory(full_path) then
			return false, "Could not create directory: " .. full_path
		end
	end

	-- Write files. Existing files are deliberately preserved.
	local paths = {}

	for path in pairs(manifest.files) do
		paths[#paths + 1] = path
	end

	table.sort(paths)

	for _, relative_path in ipairs(paths) do
		if not Layouts.Is_Safe_Path(relative_path) then
			return false, "Unsafe file path: " .. relative_path
		end

		local full_path = root .. "/" .. relative_path
		local ok, err = Write_New_File(full_path, manifest.files[relative_path])

		if not ok then
			return false, err
		end
	end

	return true, manifest
end

-- =========================================================
-- SAVE AND DELETE USER LAYOUTS
-- =========================================================

local function Read_User_Layouts()
	if vim.fn.filereadable(Layouts.user_path) ~= 1 then
		return {}
	end

	local data, err = Read_JSON(Layouts.user_path)

	if not data then
		return nil, err
	end

	if type(data.layouts) ~= "table" then
		return nil, "User layout file must contain a layouts object"
	end

	return data.layouts
end

function Layouts.Save(id, layout)
	if type(id) ~= "string" or not id:match("^[%w_-]+$") then
		return false, "Invalid layout ID"
	end

	local ok, err = Validate_Layout(id, layout)

	if not ok then
		return false, err
	end

	local user_layouts, read_error = Read_User_Layouts()

	if not user_layouts then
		return false, read_error
	end

	user_layouts[id] = Deep_Copy(layout)

	local saved, save_error = Write_JSON(Layouts.user_path, {
		version = 1,
		layouts = user_layouts,
	})

	if not saved then
		return false, save_error
	end

	local reloaded, reload_error = Layouts.Reload()

	if not reloaded then
		return false, reload_error
	end

	return true
end

function Layouts.Delete(id)
	if type(id) ~= "string" or not id:match("^[%w_-]+$") then
		return false, "Invalid layout ID"
	end

	local user_layouts, read_error = Read_User_Layouts()

	if not user_layouts then
		return false, read_error
	end

	if user_layouts[id] == nil then
		return false, "No user-saved layout exists with ID: " .. id
	end

	user_layouts[id] = nil

	local saved, save_error = Write_JSON(Layouts.user_path, {
		version = 1,
		layouts = user_layouts,
	})

	if not saved then
		return false, save_error
	end

	return Layouts.Reload()
end

return Layouts
