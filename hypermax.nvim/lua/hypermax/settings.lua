local Config = require("hypermax.config")
local Languages = require("hypermax.languages")

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
}

local function Notify(message)
	vim.notify("HyperMax: " .. message)
end

local function Save(key, value)
	Config.set(key, value)
	Notify("Saved " .. key .. ".")
end

local function Edit_Text(key, label)
	vim.ui.input({
		prompt = label .. ": ",
		default = tostring(Config.get(key) or ""),
	}, function(value)
		if value == nil then
			return
		end

		Save(key, value)
	end)
end

local function Edit_Boolean(key, label)
	local current = Config.get(key)

	vim.ui.select({ "Yes", "No" }, {
		prompt = label,
		format_item = function(item)
			if (item == "Yes") == current then
				return item .. "  (current)"
			end

			return item
		end,
	}, function(choice)
		if choice == nil then
			return
		end

		Save(key, choice == "Yes")
	end)
end

local function Edit_Language()
	local ids = Languages.Get_IDs()
	local favourites = Config.get("favourite_languages") or {}

	table.sort(ids, function(a, b)
		local function Is_Favourite(id)
			return vim.tbl_contains(favourites, id)
		end

		if Is_Favourite(a) ~= Is_Favourite(b) then
			return Is_Favourite(a)
		end

		return a < b
	end)

	vim.ui.select(ids, {
		prompt = "Choose default language",
		format_item = function(id)
			if vim.tbl_contains(favourites, id) then
				return "★ " .. id
			end

			return id
		end,
	}, function(choice)
		if choice then
			Save("default_language", choice)
		end
	end)
end

local function Edit_Favourites()
	local current = table.concat(Config.get("favourite_languages") or {}, ", ")

	vim.ui.input({
		prompt = "Favourite languages (comma-separated): ",
		default = current,
	}, function(value)
		if value == nil then
			return
		end

		local favourites = {}
		local seen = {}

		for id in value:gmatch("[^,]+") do
			id = vim.trim(id)

			if Languages.Exists(id) and not seen[id] then
				favourites[#favourites + 1] = id
				seen[id] = true
			elseif id ~= "" and not Languages.Exists(id) then
				Notify("Unknown language ignored: " .. id)
			end
		end

		Save("favourite_languages", favourites)
	end)
end

local function Edit_Manager()
	local Managers = require("hypermax.managers")
	local language = Config.get("default_language")
	local managers = Managers.Get_IDs(language)

	if #managers == 0 then
		Notify("No managers registered for " .. language .. ".")
		return
	end

	vim.ui.select(managers, {
		prompt = "Default manager for " .. language,
	}, function(choice)
		if choice then
			Save("default_manager", choice)
		end
	end)
end

local function Edit_Setting(key, label)
	if Boolean_Settings[key] then
		Edit_Boolean(key, label)
	elseif key == "default_language" then
		Edit_Language()
	elseif key == "favourite_languages" then
		Edit_Favourites()
	elseif key == "default_manager" then
		Edit_Manager()
	elseif key == "project_dir" then
		Edit_Text(key, label)
	elseif key == "default_layout" then
		Edit_Text(key, label)
	end
end

function Settings.Open()
	local entries = {
		{ label = "Default language", key = "default_language" },
		{ label = "Project starting location", key = "project_dir" },
		{ label = "Favourite languages", key = "favourite_languages" },
		{ label = "Default manager", key = "default_manager" },
		{ label = "Default layout ID", key = "default_layout" },
	}

	for key, label in pairs(Boolean_Settings) do
		entries[#entries + 1] = {
			label = label,
			key = key,
		}
	end

	table.sort(entries, function(a, b)
		return a.label < b.label
	end)

	local choices = {}

	for _, entry in ipairs(entries) do
		local value = Config.get(entry.key)

		if type(value) == "table" then
			value = table.concat(value, ", ")
		end

		choices[#choices + 1] = {
			entry = entry,
			text = entry.label .. " = " .. tostring(value),
		}
	end

	choices[#choices + 1] = {
		reset = true,
		text = "Reset all settings to defaults",
	}

	vim.ui.select(choices, {
		prompt = "HyperMax Settings",
		format_item = function(item)
			return item.text
		end,
	}, function(choice)
		if not choice then
			return
		end

		if choice.reset then
			vim.ui.select({ "Cancel", "Reset" }, {
				prompt = "Reset all HyperMax settings?",
			}, function(answer)
				if answer == "Reset" then
					Config.reset()
					Notify("Settings reset.")
					Settings.Open()
				end
			end)

			return
		end

		Edit_Setting(choice.entry.key, choice.entry.label)
	end)
end

return Settings
