-- User-configurable <Plug> mappings, one minimal default entry point, and
-- an opt-in compatibility layer for the direct shortcuts used in HyperMax 0.6.0.
-- Feature implementations remain lazy: mapping registration only installs
-- command strings and never imports dashboard/workspace/project modules.

---@class HyperMax.Keymap
---@field lhs string Mapping left-hand side exposed by HyperMax.
---@field command string Command invoked by the mapping.
---@field desc string Description shown by which-key and :map.

local Keymaps = {}

---@type HyperMax.Keymap[]
local PLUG_MAPPINGS = {
	{ lhs = "<Plug>(HyperMax-Menu)", command = "HyperMax", desc = "Open HyperMax workspace" },
	{ lhs = "<Plug>(HyperMax-CreateProject)", command = "HyperMax project create", desc = "Create a project" },
	{ lhs = "<Plug>(HyperMax-ListProjects)", command = "HyperMax project list", desc = "List projects" },
	{ lhs = "<Plug>(HyperMax-OpenLastProject)", command = "HyperMax project open-last", desc = "Open the last project" },
	{ lhs = "<Plug>(HyperMax-QuickCreateProject)", command = "HyperMax project quick-create", desc = "Quick-create a project" },
	{ lhs = "<Plug>(HyperMax-SaveLayout)", command = "HyperMax layout save", desc = "Save a layout" },
	{ lhs = "<Plug>(HyperMax-EditLayout)", command = "HyperMax layout edit", desc = "Edit a saved layout" },
	{ lhs = "<Plug>(HyperMax-LoadLayout)", command = "HyperMax layout load", desc = "Load a layout" },
	{ lhs = "<Plug>(HyperMax-ListLayouts)", command = "HyperMax layout list", desc = "Choose a layout for project creation" },
	{ lhs = "<Plug>(HyperMax-Settings)", command = "HyperMax settings", desc = "Open settings" },
	{ lhs = "<Plug>(HyperMax-Workspace)", command = "HyperMax workspace open", desc = "Open workspace" },
	{ lhs = "<Plug>(HyperMax-Palette)", command = "HyperMax workspace palette", desc = "Open command palette" },
	{ lhs = "<Plug>(HyperMax-Tasks)", command = "HyperMax workspace tasks", desc = "Open task board" },
	{ lhs = "<Plug>(HyperMax-Runs)", command = "HyperMax workspace runs", desc = "Open run configurations" },
	{ lhs = "<Plug>(HyperMax-Diagnostics)", command = "HyperMax workspace diagnostics", desc = "Open project diagnostics" },
	{ lhs = "<Plug>(HyperMax-FindFiles)", command = "HyperMax workspace find-files", desc = "Find project files" },
	{ lhs = "<Plug>(HyperMax-SearchText)", command = "HyperMax workspace search-text", desc = "Search project text" },
	{ lhs = "<Plug>(HyperMax-History)", command = "HyperMax history open", desc = "Open save history" },
	{ lhs = "<Plug>(HyperMax-SavePoint)", command = "HyperMax history save", desc = "Create a hard save point" },
	{ lhs = "<Plug>(HyperMax-Tutorial)", command = "HyperMax tutorial", desc = "Open tutorials" },
	{ lhs = "<Plug>(HyperMax-Health)", command = "HyperMax health", desc = "Run health checks" },
	{ lhs = "<Plug>(HyperMax-ConvertProject)", command = "HyperMax project convert", desc = "Convert a directory into a project" },
	{ lhs = "<Plug>(HyperMax-UndoConversion)", command = "HyperMax project undo-conversion", desc = "Undo project conversion" },
	{ lhs = "<Plug>(HyperMax-ScrapeProject)", command = "HyperMax project scrape", desc = "Remove project metadata" },
	{ lhs = "<Plug>(HyperMax-ShowConfig)", command = "HyperMax config", desc = "Show configuration" },
}

local DEFAULT_MENU_MAPPING = "<leader>++"
local DEFAULT_MENU_PLUG = "<Plug>(HyperMax-Menu)"
local default_mapping_owned = false

-- This list reproduces the non-menu direct bindings from the 0.6.0 keymap
-- module. The menu entry itself remains the 0.7.x <leader>++ workspace action.
---@class HyperMax.LegacyKeymap
---@field lhs string Shortcut left-hand side.
---@field rhs string Namespaced <Plug> mapping invoked by the shortcut.
---@field desc string Mapping description.

---@type HyperMax.LegacyKeymap[]
local LEGACY_MAPPINGS = {
	{ lhs = "<leader>+T", rhs = "<Plug>(HyperMax-Tutorial)", desc = "Open tutorials" },
	{ lhs = "<leader>+p", rhs = "<Plug>(HyperMax-ListProjects)", desc = "List projects" },
	{ lhs = "<D-p>", rhs = "<Plug>(HyperMax-ListProjects)", desc = "List projects" },
	{ lhs = "<D-o>", rhs = "<Plug>(HyperMax-OpenLastProject)", desc = "Open last project" },
	{ lhs = "<leader>+n", rhs = "<Plug>(HyperMax-CreateProject)", desc = "Create a project" },
	{ lhs = "<leader>+r", rhs = "<Plug>(HyperMax-CreateProject)", desc = "Open project creation wizard" },
	{ lhs = "<leader>+o", rhs = "<Plug>(HyperMax-OpenLastProject)", desc = "Open last project" },
	{ lhs = "<leader>+q", rhs = "<Plug>(HyperMax-QuickCreateProject)", desc = "Quick-create a project" },
	{ lhs = "<leader>+s", rhs = "<Plug>(HyperMax-Settings)", desc = "Open settings" },
	{ lhs = "<leader>+H", rhs = "<Plug>(HyperMax-History)", desc = "Browse save history" },
	{ lhs = "<leader>+S", rhs = "<Plug>(HyperMax-SavePoint)", desc = "Create a hard save point" },
	{ lhs = "<leader>+l", rhs = "<Plug>(HyperMax-LoadLayout)", desc = "Load a layout" },
	{ lhs = "<leader>+L", rhs = "<Plug>(HyperMax-SaveLayout)", desc = "Save current project as a layout" },
	{ lhs = "<leader>+c", rhs = "<Plug>(HyperMax-ShowConfig)", desc = "Show configuration" },
	{ lhs = "<leader>+m", rhs = "<Plug>(HyperMax-Workspace)", desc = "Open workspace" },
	{ lhs = "<leader>+t", rhs = "<Plug>(HyperMax-Tasks)", desc = "Open project task board" },
	{ lhs = "<leader>+w", rhs = "<Plug>(HyperMax-Runs)", desc = "Open project run configurations" },
	{ lhs = "<leader>+f", rhs = "<Plug>(HyperMax-FindFiles)", desc = "Find project files" },
	{ lhs = "<leader>+/", rhs = "<Plug>(HyperMax-SearchText)", desc = "Search project text" },
	{ lhs = "<leader>+x", rhs = "<Plug>(HyperMax-Diagnostics)", desc = "Review project diagnostics" },
	{ lhs = "<leader>+<Space>", rhs = "<Plug>(HyperMax-Palette)", desc = "Open command palette" },
	{ lhs = "<leader>+h", rhs = "<Plug>(HyperMax-Health)", desc = "Run health checks" },
	{ lhs = "<leader>+C", rhs = "<Plug>(HyperMax-ConvertProject)", desc = "Convert current folder into a project" },
	{ lhs = "<leader>+u", rhs = "<Plug>(HyperMax-UndoConversion)", desc = "Undo project conversion" },
	{ lhs = "<leader>+X", rhs = "<Plug>(HyperMax-ScrapeProject)", desc = "Remove project metadata" },
}

---@param mode string
---@param lhs string
---@return boolean
local function Has_Mapping(mode, lhs)
	local ok, mapping = pcall(vim.fn.maparg, lhs, mode)
	return ok and type(mapping) == "string" and mapping ~= ""
end

---@param lhs string
---@return table|nil
local function Get_Mapping(lhs)
	local ok, mapping = pcall(vim.fn.maparg, lhs, "n", false, true)
	if ok and type(mapping) == "table" and next(mapping) ~= nil then
		return mapping
	end
	return nil
end

---@return nil
local function Register_Plug_Mappings()
	for _, mapping in ipairs(PLUG_MAPPINGS) do
		if not Has_Mapping("n", mapping.lhs) then
			vim.keymap.set("n", mapping.lhs, function()
				vim.cmd(mapping.command)
			end, {
				desc = "HyperMax: " .. mapping.desc,
				silent = true,
			})
		end
	end
end

---@return nil
local function Register_Default_Mappings()
	local Config = require("hypermax.config")
	local enabled = Config.get("default_keymaps") == true
	local current = Get_Mapping(DEFAULT_MENU_MAPPING)

	if enabled then
		-- Never replace a mapping already owned by the user or another plugin.
		if not Has_Mapping("n", DEFAULT_MENU_MAPPING) then
			local ok = pcall(vim.keymap.set, "n", DEFAULT_MENU_MAPPING, DEFAULT_MENU_PLUG, {
				desc = "HyperMax: open workspace",
				silent = true,
				remap = true,
				unique = true,
			})
			default_mapping_owned = ok
		end
	elseif default_mapping_owned then
		if current and current.rhs == DEFAULT_MENU_PLUG and current.desc == "HyperMax: open workspace" then
			pcall(vim.keymap.del, "n", DEFAULT_MENU_MAPPING)
		end
		default_mapping_owned = false
	end
end

local owned_legacy_mappings = {}

local function Remove_Legacy_Mappings()
	for index = #owned_legacy_mappings, 1, -1 do
		local mapping = owned_legacy_mappings[index]
		local current = Get_Mapping(mapping.lhs)
		if current and current.rhs == mapping.rhs and current.desc == mapping.desc then
			pcall(vim.keymap.del, "n", mapping.lhs)
		end
		owned_legacy_mappings[index] = nil
	end
end

local function Register_Legacy_Mappings()
	Remove_Legacy_Mappings()
	local Config = require("hypermax.config")
	if Config.get("legacy_shortcuts") ~= true then
		return
	end

	for _, mapping in ipairs(LEGACY_MAPPINGS) do
		if not Has_Mapping("n", mapping.lhs) then
			local description = "HyperMax legacy: " .. mapping.desc
			local ok = pcall(vim.keymap.set, "n", mapping.lhs, mapping.rhs, {
				desc = description,
				silent = true,
				remap = true,
				unique = true,
			})
			if ok then
				owned_legacy_mappings[#owned_legacy_mappings + 1] = {
					lhs = mapping.lhs,
					rhs = mapping.rhs,
					desc = description,
				}
			end
		end
	end
end

---Register HyperMax <Plug> mappings, the optional default mapping, and any
---explicitly enabled 0.6.0 compatibility shortcuts. Safe to call repeatedly.
---@return nil
function Keymaps.Setup()
	Register_Plug_Mappings()
	Keymaps.Refresh_Default_Mapping()
end

---Refresh mappings after a saved configuration change.
---@return nil
function Keymaps.Refresh_Default_Mapping()
	Register_Default_Mappings()
	Register_Legacy_Mappings()
end

Keymaps.Refresh_Mappings = Keymaps.Refresh_Default_Mapping

---@return HyperMax.Keymap[] mappings
function Keymaps.Get_Plug_Mappings()
	---@type HyperMax.Keymap[]
	local result = {}
	for index, mapping in ipairs(PLUG_MAPPINGS) do
		result[index] = vim.deepcopy(mapping)
	end
	return result
end

---@return HyperMax.LegacyKeymap[] mappings
function Keymaps.Get_Legacy_Mappings()
	---@type HyperMax.LegacyKeymap[]
	local result = {}
	for index, mapping in ipairs(LEGACY_MAPPINGS) do
		result[index] = vim.deepcopy(mapping)
	end
	return result
end

---@return string
function Keymaps.Get_Default_Menu_Mapping()
	return DEFAULT_MENU_MAPPING
end

return Keymaps
