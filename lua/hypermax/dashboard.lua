local Dashboard = {}

local uv = vim.uv or vim.loop
local Project_Config = require("hypermax.project_config")

local MAX_TREE_ENTRIES = 200
local MAX_TREE_DEPTH = 5

local IGNORED_DIRECTORIES = {
	[".git"] = true,
	[".hmc"] = true,
	["node_modules"] = true,
	["vendor"] = true,
	["target"] = true,
	["build"] = true,
	["dist"] = true,
	[".venv"] = true,
	["venv"] = true,
}

local State = {
	root = nil,
	buffer = nil,
	expanded = {},
	tree = {},
	metadata = {},
}

-- =========================================================
-- UTILITIES
-- =========================================================

local function Join(...)
	return table.concat({ ... }, "/"):gsub("/+", "/")
end

local function Notify(message, level)
	vim.notify("HyperMax: " .. message, level or vim.log.levels.INFO)
end

local function Is_Directory(path)
	local stat = uv.fs_stat(path)
	return stat ~= nil and stat.type == "directory"
end

local function Is_File(path)
	local stat = uv.fs_stat(path)
	return stat ~= nil and stat.type == "file"
end

local function Format_Date(timestamp)
	if type(timestamp) ~= "number" then
		return "Unknown"
	end

	return os.date("%Y-%m-%d %H:%M", timestamp)
end

local function Get_Project_Metadata(root)
	local loaded, err = Project_Config.Load(root)

	if not loaded then
		return nil, err
	end

	local basics = loaded.basics or {}
	local project = basics.project or {}

	return {
		name = project.name or vim.fs.basename(root),
		root = project.root or root,
		language = project.language or "unknown",
		manager = project.manager or "native",
		creator = project.creator or "unknown",
		created_at = project.created_at,
		git_enabled = basics.git and basics.git.enabled == true or false,
	}
end

-- =========================================================
-- PROJECT TREE
-- =========================================================

local function Build_Tree(directory, depth, counter)
	local entries = {}
	local handle = uv.fs_scandir(directory)

	if not handle then
		return entries
	end

	while counter.count < MAX_TREE_ENTRIES do
		local name, kind = uv.fs_scandir_next(handle)

		if not name then
			break
		end

		if not (kind == "directory" and IGNORED_DIRECTORIES[name]) then
			if kind == "directory" or kind == "file" then
				local path = Join(directory, name)

				local entry = {
					name = name,
					path = path,
					type = kind,
					children = {},
				}

				counter.count = counter.count + 1

				if kind == "directory" then
					if depth < MAX_TREE_DEPTH and counter.count < MAX_TREE_ENTRIES then
						entry.children = Build_Tree(path, depth + 1, counter)
					end

					-- Expand root folders by default.
					if depth < 1 then
						State.expanded[path] = true
					end
				end

				entries[#entries + 1] = entry
			end
		end
	end

	table.sort(entries, function(a, b)
		if a.type ~= b.type then
			return a.type == "directory"
		end

		return a.name:lower() < b.name:lower()
	end)

	return entries
end

local function Render_Tree(entries, depth, lines, items, line_by_path)
	local indent = string.rep("  ", depth)

	for _, entry in ipairs(entries) do
		local line

		if entry.type == "directory" then
			local expanded = State.expanded[entry.path] == true
			local arrow = expanded and "▾ " or "▸ "

			line = indent .. arrow .. "📁 " .. entry.name .. "/"
		else
			line = indent .. "  " .. entry.name
		end

		lines[#lines + 1] = line

		local line_number = #lines
		items[line_number] = entry
		line_by_path[entry.path] = line_number

		if entry.type == "directory" and State.expanded[entry.path] then
			Render_Tree(entry.children, depth + 1, lines, items, line_by_path)
		end
	end
end

-- =========================================================
-- DASHBOARD RENDERING
-- =========================================================

local function Render()
	if not State.buffer or not vim.api.nvim_buf_is_valid(State.buffer) then
		return
	end

	local root = State.root
	local metadata = State.metadata

	local lines = {}
	local items = {}
	local line_by_path = {}

	local function Add(text)
		lines[#lines + 1] = text
	end

	Add(
		"╔══════════════════════════════════════════════╗"
	)
	Add("║                 HYPERMAX                     ║")
	Add("║              PROJECT DASHBOARD              ║")
	Add(
		"╚══════════════════════════════════════════════╝"
	)
	Add("")

	-- Project information.
	Add("  PROJECT INFORMATION")
	Add(
		"  ────────────────────────────────────────────"
	)
	Add("  Name:       " .. metadata.name)
	Add("  Language:   " .. metadata.language)
	Add("  Manager:    " .. metadata.manager)
	Add("  Creator:    " .. metadata.creator)
	Add("  Created:    " .. Format_Date(metadata.created_at))
	Add("  Location:   " .. root)
	Add("")

	-- Project tree.
	Add("  PROJECT FILES")
	Add(
		"  ────────────────────────────────────────────"
	)

	if #State.tree == 0 then
		Add("  (No project files found)")
	else
		Render_Tree(State.tree, 0, lines, items, line_by_path)
	end

	Add("")
	Add("  GIT")
	Add(
		"  ────────────────────────────────────────────"
	)

	if metadata.git_enabled then
		Add("  Repository detected in project metadata.")
		Add("  Git actions will be available here.")
	else
		Add("  No Git repository recorded for this project.")
		Add("  Git status and actions will be added next.")
	end

	Add("")
	Add("  DIAGNOSTICS")
	Add(
		"  ────────────────────────────────────────────"
	)
	Add("  Diagnostics panel will be connected next.")
	Add("")

	Add("  SHORTCUTS")
	Add(
		"  ────────────────────────────────────────────"
	)
	Add("  Enter   Open file / expand or collapse folder")
	Add("  r       Refresh dashboard")
	Add("  q       Close dashboard")
	Add("")

	local buf = State.buffer

	vim.bo[buf].modifiable = true

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	vim.bo[buf].modifiable = false

	State.items = items
	State.line_by_path = line_by_path
end

-- =========================================================
-- DASHBOARD ACTIONS
-- =========================================================

local function Get_Selected_Item()
	local line = vim.api.nvim_win_get_cursor(0)[1]
	return State.items and State.items[line]
end

local function Open_Selected()
	local entry = Get_Selected_Item()

	if not entry then
		return
	end

	if entry.type == "directory" then
		State.expanded[entry.path] = not State.expanded[entry.path]

		Render()

		local new_line = State.line_by_path[entry.path]

		if new_line then
			vim.api.nvim_win_set_cursor(0, { new_line, 0 })
		end

		return
	end

	if Is_File(entry.path) then
		vim.cmd("edit " .. vim.fn.fnameescape(entry.path))
	else
		Notify("File no longer exists: " .. entry.path, vim.log.levels.WARN)
	end
end

local function Refresh()
	local metadata, err = Get_Project_Metadata(State.root)

	if not metadata then
		Notify(tostring(err), vim.log.levels.ERROR)
		return
	end

	State.metadata = metadata
	State.tree = Build_Tree(State.root, 0, { count = 0 })

	Render()
end

local function Set_Keymaps(buf)
	local function Map(key, callback, description)
		vim.keymap.set("n", key, callback, {
			buffer = buf,
			silent = true,
			noremap = true,
			desc = description,
		})
	end

	Map("<CR>", Open_Selected, "Open file or toggle folder")
	Map("r", Refresh, "Refresh HyperMax dashboard")

	Map("q", function()
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end, "Close HyperMax dashboard")
end

-- =========================================================
-- PUBLIC API
-- =========================================================

function Dashboard.Is_Project(root)
	root = vim.fn.fnamemodify(root or vim.fn.getcwd(), ":p")

	return Is_Directory(Join(root, ".hmc"))
end

function Dashboard.Find_Project_Root(path)
	path = vim.fn.fnamemodify(vim.fn.expand(path or vim.fn.getcwd()), ":p")

	-- If a file was supplied, start searching from its directory.
	if Is_File(path) then
		path = vim.fn.fnamemodify(path, ":h")
	end

	while path and path ~= "" do
		if Dashboard.Is_Project(path) then
			return path
		end

		local parent = vim.fn.fnamemodify(path, ":h")

		if parent == path then
			break
		end

		path = parent
	end

	return nil
end

function Dashboard.Open(project_root)
	project_root = vim.fn.fnamemodify(vim.fn.expand(project_root or vim.fn.getcwd()), ":p")

	if not Dashboard.Is_Project(project_root) then
		Notify("Not a HyperMax project: " .. project_root, vim.log.levels.WARN)
		return false
	end

	local metadata, err = Get_Project_Metadata(project_root)

	if not metadata then
		Notify("Could not load project metadata: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end

	State.root = project_root
	State.metadata = metadata
	State.expanded = {}
	State.tree = Build_Tree(project_root, 0, { count = 0 })

	local buf = vim.api.nvim_create_buf(false, true)

	State.buffer = buf
	State.items = {}
	State.line_by_path = {}

	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = true
	vim.bo[buf].filetype = "hypermaxdashboard"

	vim.api.nvim_buf_set_name(buf, "HyperMax://" .. metadata.name)

	vim.api.nvim_set_current_buf(buf)

	Set_Keymaps(buf)
	Render()

	return true
end

function Dashboard.Open_Current_Project()
	return Dashboard.Open(vim.fn.getcwd())
end

function Dashboard.Refresh()
	Refresh()
end

return Dashboard
