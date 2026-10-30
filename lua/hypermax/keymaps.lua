-- User-configurable <Plug> mappings and one conflict-safe default entry point.
-- HyperMax does not populate the user's global keymap namespace with dozens
-- of mappings. Feature mappings are exposed through <Plug> instead.

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

---@param mode string
---@param lhs string
---@return boolean
local function Has_Mapping(mode, lhs)
	local ok, mapping = pcall(vim.fn.maparg, lhs, mode)
	return ok and type(mapping) == "string" and mapping ~= ""
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
	local current = vim.fn.maparg(DEFAULT_MENU_MAPPING, "n", false, true)

	if enabled then
		-- Never replace a mapping already owned by the user or another plugin.
		if not Has_Mapping("n", DEFAULT_MENU_MAPPING) then
			vim.keymap.set("n", DEFAULT_MENU_MAPPING, DEFAULT_MENU_PLUG, {
				desc = "HyperMax: open workspace",
				silent = true,
			})
		end
	elseif type(current) == "table"
		and current.rhs == DEFAULT_MENU_PLUG
		and current.desc == "HyperMax: open workspace" then
		-- Remove only the exact mapping HyperMax itself installed. A user map
		-- that happens to use the same LHS is never removed.
		pcall(vim.keymap.del, "n", DEFAULT_MENU_MAPPING)
	end
end

---Register HyperMax <Plug> mappings and the optional minimal default mapping.
---Safe to call more than once. No feature module is loaded here.
---@return nil
function Keymaps.Setup()
	Register_Plug_Mappings()
	Register_Default_Mappings()
end

---Refresh only the optional default mapping after a configuration change.
---@return nil
function Keymaps.Refresh_Default_Mapping()
	Register_Default_Mappings()
end

---@return HyperMax.Keymap[] mappings
function Keymaps.Get_Plug_Mappings()
	---@type HyperMax.Keymap[]
	local result = {}
	for index, mapping in ipairs(PLUG_MAPPINGS) do
		result[index] = vim.deepcopy(mapping)
	end
	return result
end

---@return string
function Keymaps.Get_Default_Menu_Mapping()
	return DEFAULT_MENU_MAPPING
end

return Keymaps
