-- Hierarchical HyperMax settings. Global defaults are kept separate from
-- project-local workspace settings stored in .hmc/config.json.
local Config = require("hypermax.config")
local Languages = require("hypermax.languages")
local Project_Config = require("hypermax.project_config")

local Settings = {}

local Boolean_Settings = {
	create_missing_dir = "Create missing project directories",
	open_after_create = "Open project after creation",
	show_progress = "Show progress window",
	show_command_output = "Show command output",
	confirm_before_create = "Confirm before creating projects",
	create_readme = "Generate README.md",
	create_gitignore = "Generate .gitignore",
	create_credits = "Generate CREDITS.md",
	create_default_directories = "Generate default directories",
	remember_last_language = "Remember last language",
	remember_last_manager = "Remember last manager",
	default_keymaps = "Install the default workspace keymap",
}

local CONTEXT_POSITIONS = { "center", "N", "NE", "E", "SE", "S", "SW", "W", "NW", "NS", "EW" }

local function Notify(message, level)
	vim.notify("HyperMax: " .. message, level or vim.log.levels.INFO)
end

local function Resolve_Root(root)
	local Dashboard = require("hypermax.dashboard")
	return Dashboard.Find_Project_Root(root or vim.fn.getcwd())
end

local function Refresh_Project(root)
	if not root then return end
	local Dashboard = require("hypermax.dashboard")
	local state = Dashboard.Get_State()
	if state.root == root then
		state.settings = Project_Config.Get_Project_Settings(root) or {}
		state.metadata = nil
		Dashboard.Refresh()
		local updated = Dashboard.Get_State()
		if updated.settings.show_tabs == false then vim.o.showtabline = 0 else vim.o.showtabline = 2 end
	end
	local Flow = require("hypermax.flow")
	if Flow.Get_State().root == root then
		Flow.Refresh()
	end
end

local function Save_Project(root, key, value)
	if not root then
		Notify("Open a HyperMax project to edit workspace settings", vim.log.levels.WARN)
		return false
	end
	local ok, err = Project_Config.Save_Project_Settings(root, { [key] = value })
	if not ok then
		Notify("Could not save project setting: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end
	Refresh_Project(root)
	Notify("Saved workspace setting: " .. key)
	return true
end

local function Save_Global(key, value)
	local ok, err = Config.set(key, value)
	if not ok then
		Notify("Could not save global setting '" .. key .. "': " .. tostring(err), vim.log.levels.ERROR)
		return false
	end
	if key == "default_keymaps" then
		require("hypermax.keymaps").Refresh_Default_Mapping()
	end
	Notify("Saved global setting: " .. key)
	return true
end

local function Edit_Boolean(key, label)
	local current = Config.get(key)
	vim.ui.select({ "Yes", "No" }, {
		prompt = label,
		format_item = function(item)
			if (item == "Yes") == current then return item .. "  (current)" end
			return item
		end,
	}, function(choice)
		if choice ~= nil then Save_Global(key, choice == "Yes") end
	end)
end

local function Edit_Text(key, label)
	vim.ui.input({
		prompt = label .. ": ",
		default = tostring(Config.get(key) or ""),
	}, function(value)
		if value ~= nil then Save_Global(key, value) end
	end)
end

local function Edit_Language()
	local ids = Languages.Get_IDs()
	local favourites = Config.get("favourite_languages") or {}
	table.sort(ids, function(a, b)
		local af = vim.tbl_contains(favourites, a)
		local bf = vim.tbl_contains(favourites, b)
		if af ~= bf then return af end
		return a < b
	end)
	vim.ui.select(ids, {
		prompt = "Choose default language",
		format_item = function(id)
			return vim.tbl_contains(favourites, id) and ("★ " .. id) or id
		end,
	}, function(choice)
		if choice then Save_Global("default_language", choice) end
	end)
end

local function Edit_Favourites()
	local current = table.concat(Config.get("favourite_languages") or {}, ", ")
	vim.ui.input({ prompt = "Favourite languages (comma-separated): ", default = current }, function(value)
		if value == nil then return end
		local favourites, seen = {}, {}
		for id in value:gmatch("[^,]+") do
			id = vim.trim(id)
			if Languages.Exists(id) and not seen[id] then
				favourites[#favourites + 1], seen[id] = id, true
			elseif id ~= "" and not Languages.Exists(id) then
				Notify("Unknown language ignored: " .. id, vim.log.levels.WARN)
			end
		end
		Save_Global("favourite_languages", favourites)
	end)
end

local function Edit_Manager()
	local Managers = require("hypermax.managers")
	local language = Config.get("default_language")
	local managers = Managers.Get_IDs(language)
	if #managers == 0 then Notify("No managers registered for " .. language, vim.log.levels.WARN); return end
	vim.ui.select(managers, { prompt = "Default manager for " .. language }, function(choice)
		if choice then Save_Global("default_manager", choice) end
	end)
end

local function Edit_Global_Setting(key, label)
	if Boolean_Settings[key] then Edit_Boolean(key, label)
	elseif key == "default_language" then Edit_Language()
	elseif key == "favourite_languages" then Edit_Favourites()
	elseif key == "default_manager" then Edit_Manager()
	elseif key == "project_dir" or key == "default_layout" then Edit_Text(key, label)
	end
end

local function Project_Settings(root)
	return Project_Config.Get_Project_Settings(root) or {}
end

local function Edit_Project_Boolean(root, key, label)
	local current = Project_Settings(root)[key] == true
	vim.ui.select({ "Yes", "No" }, {
		prompt = label,
		format_item = function(item)
			if (item == "Yes") == current then return item .. "  (current)" end
			return item
		end,
	}, function(choice)
		if choice ~= nil then Save_Project(root, key, choice == "Yes") end
	end)
end

local function Edit_Entry_Point(root, field, label)
	local settings = Project_Settings(root)
	local entry = settings.entry_point or {}
	vim.ui.input({
		prompt = label .. (field == "file" and " (project-relative path): " or ": "),
		default = tostring(entry[field] or (field == "function" and "main" or "")),
	}, function(value)
		if value == nil then return end
		value = vim.trim(value)
		if field == "file" and value ~= "" then
			local Filesystem = require("hypermax.filesystem")
			local safe, err = Filesystem.Safe_Child(root, value)
			if not safe then Notify("Invalid entry point: " .. tostring(err), vim.log.levels.ERROR); return end
			value = value:gsub("\\", "/")
		end
		entry[field] = value
		Save_Project(root, "entry_point", entry)
	end)
end

local function Edit_Excluded_Paths(root)
	local values = Project_Settings(root).exclude_paths or {}
	vim.ui.input({
		prompt = "Paths/patterns to hide (comma-separated, relative to project): ",
		default = table.concat(values, ", "),
	}, function(value)
		if value == nil then return end
		local result, seen = {}, {}
		for item in value:gmatch("[^,]+") do
			item = vim.trim(item):gsub("\\", "/")
			if item ~= "" and item:sub(1, 1) ~= "/" and not item:match("^%a:") then
				local safe = true
				for part in item:gmatch("[^/]+") do if part == ".." or part == "." then safe = false end end
				if safe and not seen[item] then result[#result + 1], seen[item] = item, true end
			elseif item ~= "" then
				Notify("Ignored unsafe exclude pattern: " .. item, vim.log.levels.WARN)
			end
		end
		Save_Project(root, "exclude_paths", result)
	end)
end

local function Edit_Context_Position(root)
	vim.ui.select(CONTEXT_POSITIONS, {
		prompt = "Context window position",
		format_item = function(value)
			if value == "NS" then return "NS / middle" end
			if value == "EW" then return "EW / middle" end
			return value
		end,
	}, function(choice)
		if choice then Save_Project(root, "context_position", choice) end
	end)
end

local function Edit_Pinned_Position(root)
	vim.ui.select({ "top", "bottom" }, { prompt = "Pinned task section position" }, function(choice)
		if choice then Save_Project(root, "pinned_tasks_position", choice) end
	end)
end

local function Edit_Project_Setting(root, key, label)
	if key == "show_hidden" or key == "show_tabs" or key == "auto_save_after_success" then
		Edit_Project_Boolean(root, key, label)
	elseif key == "entry_point_file" then
		Edit_Entry_Point(root, "file", label)
	elseif key == "entry_point_function" then
		Edit_Entry_Point(root, "function", label)
	elseif key == "exclude_paths" then
		Edit_Excluded_Paths(root)
	elseif key == "context_position" then
		Edit_Context_Position(root)
	elseif key == "pinned_tasks_position" then
		Edit_Pinned_Position(root)
	end
end

local function Open_Global_Settings(root)
	local entries = {
		{ label = "Default language", key = "default_language" },
		{ label = "Project starting location", key = "project_dir" },
		{ label = "Favourite languages", key = "favourite_languages" },
		{ label = "Default manager", key = "default_manager" },
		{ label = "Default layout ID", key = "default_layout" },
	}
	for key, label in pairs(Boolean_Settings) do entries[#entries + 1] = { label = label, key = key } end
	table.sort(entries, function(a, b) return a.label < b.label end)
	local choices = {}
	for _, entry in ipairs(entries) do
		local value = Config.get(entry.key)
		if type(value) == "table" then value = table.concat(value, ", ") end
		choices[#choices + 1] = { entry = entry, text = entry.label .. " = " .. tostring(value) }
	end
	choices[#choices + 1] = { reset = true, text = "Reset all global settings to defaults" }
	choices[#choices + 1] = { back = true, text = "← Back" }
	vim.ui.select(choices, {
		prompt = "Global HyperMax Settings",
		format_item = function(item) return item.text end,
	}, function(choice)
		if not choice then return end
		if choice.back then Settings.Open(root)
		elseif choice.reset then
			vim.ui.select({ "Cancel", "Reset" }, { prompt = "Reset all global HyperMax settings?" }, function(answer)
				if answer == "Reset" then Config.reset(); Notify("Global settings reset."); Settings.Open(root) end
			end)
		else
			Edit_Global_Setting(choice.entry.key, choice.entry.label)
		end
	end)
end

local function Open_Category(root, category)
	local settings = root and Project_Settings(root) or {}
	local categories = {
		["Project creation"] = {
			{ label = "Default language", key = "default_language", scope = "global" },
			{ label = "Default manager", key = "default_manager", scope = "global" },
			{ label = "Project starting location", key = "project_dir", scope = "global" },
			{ label = "Favourite languages", key = "favourite_languages", scope = "global" },
			{ label = "Open after creation", key = "open_after_create", scope = "global" },
			{ label = "Confirm before creation", key = "confirm_before_create", scope = "global" },
			{ label = "Create missing directories", key = "create_missing_dir", scope = "global" },
		},
		["Saving and history"] = {
			{ label = "Automatically save after successful run", key = "auto_save_after_success", scope = "project", value = settings.auto_save_after_success },
			{ label = "Create a hard save point now", requires_project = true, action = function() local ok, result = require("hypermax.history").Save(root, "hard"); Notify(ok and ("Hard save created: " .. result.id) or tostring(result), ok and vim.log.levels.INFO or vim.log.levels.ERROR) end },
			{ label = "View save points / rollback", requires_project = true, action = function() require("hypermax.history").Open(root) end },
		},
		["Workspace"] = {
			{ label = "Custom entry point file", key = "entry_point_file", scope = "project" },
			{ label = "Custom entry point function", key = "entry_point_function", scope = "project" },
			{ label = "Show hidden files and folders", key = "show_hidden", scope = "project", value = settings.show_hidden },
			{ label = "Files/folders to exclude", key = "exclude_paths", scope = "project", value = table.concat(settings.exclude_paths or {}, ", ") },
			{ label = "Show Neovim tabline", key = "show_tabs", scope = "project", value = settings.show_tabs },
			{ label = "Context window position", key = "context_position", scope = "project", value = settings.context_position },
			{ label = "Pinned task section position", key = "pinned_tasks_position", scope = "project", value = settings.pinned_tasks_position },
		},
		["Layouts"] = {
			{ label = "Default layout ID", key = "default_layout", scope = "global" },
			{ label = "Save current project as layout", action = function() require("hypermax.project").Save_Layout() end },
			{ label = "Apply a layout to a new project", action = function() require("hypermax.project").Load_Layout() end },
			{ label = "Edit a saved layout", action = function() require("hypermax.project").Edit_Layout() end },
			{ label = "List saved layouts", action = function() local Layouts = require("hypermax.layouts"); local ids = Layouts.Get_IDs(); vim.ui.select(ids, { prompt = "Saved layouts" }, function(id) if id then Notify("Layout: " .. id) end end) end },
		},
		["Interface"] = {
			{ label = "Show project-creation progress", key = "show_progress", scope = "global" },
			{ label = "Show command output", key = "show_command_output", scope = "global" },
			{ label = "Install default <leader>++ mapping", key = "default_keymaps", scope = "global" },
		},
		["Utilities"] = {
			{ label = "Open HyperMax workspace", requires_project = true, action = function() require("hypermax.workspace").Open(root) end },
			{ label = "Open project diagnostics", requires_project = true, action = function() require("hypermax.workspace").Diagnostics(root) end },
			{ label = "Run health checks", action = function() require("hypermax.keymaps").Run_Health_Check() end },
		},
	}

	local entries = categories[category] or {}
	local choices = {}
	for _, entry in ipairs(entries) do
		if root or (entry.scope ~= "project" and not entry.requires_project) then
			local suffix = ""
			if entry.scope == "global" then
				local value = Config.get(entry.key)
				if type(value) == "table" then value = table.concat(value, ", ") end
				suffix = " = " .. tostring(value)
			elseif entry.value ~= nil then
				suffix = " = " .. tostring(entry.value)
			end
			choices[#choices + 1] = { entry = entry, text = entry.label .. suffix }
		end
	end
	choices[#choices + 1] = { back = true, text = "← Back" }
	vim.ui.select(choices, {
		prompt = "HyperMax Settings  /  " .. category,
		format_item = function(item) return item.text end,
	}, function(choice)
		if not choice then return end
		if choice.back then Settings.Open(root); return end
		local entry = choice.entry
		if entry.action then entry.action()
		elseif entry.scope == "global" then Edit_Global_Setting(entry.key, entry.label)
		elseif entry.scope == "project" then Edit_Project_Setting(root, entry.key, entry.label) end
	end)
end

function Settings.Open(root)
	root = Resolve_Root(root)
	local choices = {
		"Project creation",
		"Saving and history",
		"Layouts",
		"Interface",
		"Utilities",
		"Global settings",
	}
	if root then choices[#choices + 1] = "Workspace" end
	choices[#choices + 1] = "Close"
	vim.ui.select(choices, { prompt = "HyperMax Settings" }, function(choice)
		if not choice or choice == "Close" then return end
		if choice == "Global settings" then Open_Global_Settings(root)
		else Open_Category(root, choice) end
	end)
end

return Settings
