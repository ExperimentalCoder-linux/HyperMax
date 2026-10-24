local Dashboard = {}

local uv = vim.uv or vim.loop
local Project_Config = require("hypermax.project_config")

local MAX_TREE_ENTRIES = 200
local MAX_TREE_DEPTH = 5
local PANEL_WIDTH = 34

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
	window = nil,
	expanded = {},
	tree = {},
	metadata = {},
	items = {},
	line_by_path = {},
}

local Highlight_Namespace = vim.api.nvim_create_namespace("HyperMaxDashboard")

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

	return os.date("%Y-%m-%d", timestamp)
end

local function Define_Highlights()
	vim.api.nvim_set_hl(0, "HyperMaxHeader", { fg = "#89b4fa", bold = true })
	vim.api.nvim_set_hl(0, "HyperMaxSubtitle", { fg = "#a6adc8", italic = true })
	vim.api.nvim_set_hl(0, "HyperMaxSection", { fg = "#94e2d5", bold = true })
	vim.api.nvim_set_hl(0, "HyperMaxMuted", { fg = "#6c7086" })
	vim.api.nvim_set_hl(0, "HyperMaxDirectory", { fg = "#89b4fa", bold = true })
	vim.api.nvim_set_hl(0, "HyperMaxFile", { fg = "#cdd6f4" })
	vim.api.nvim_set_hl(0, "HyperMaxEntry", { fg = "#a6e3a1", bold = true })
	vim.api.nvim_set_hl(0, "HyperMaxKey", { fg = "#f9e2af", bold = true })
	vim.api.nvim_set_hl(0, "HyperMaxPanel", { link = "Normal" })
end

local function Get_Project_Metadata(root)
	local loaded, err = Project_Config.Load(root)

	if not loaded then
		return nil, err
	end

	local basics = loaded.basics or {}
	local project = basics.project or {}
	local entry_point = project.entry_point or {}

	local entry_file = entry_point.file or project.entry_file or ""
	entry_file = tostring(entry_file):gsub("\\", "/"):gsub("^%./", "")

	return {
		name = project.name or vim.fs.basename(root),
		root = project.root or root,
		language = project.language or "unknown",
		manager = project.manager or "native",
		creator = project.creator or "unknown",
		created_at = project.created_at,
		entry_file = entry_file,
		entry_function = entry_point["function"] or entry_point.function_name or project.entry_function or "main",
		git_enabled = basics.git and basics.git.enabled == true or false,
	}
end

local function File_Icon(name)
	local extension = name:match("%.([^%.]+)$")
	extension = extension and extension:lower() or ""

	local icons = {
		lua = "λ",
		c = "C",
		h = "H",
		cpp = "C++",
		cc = "C++",
		hpp = "H++",
		py = "Py",
		rs = "Rs",
		js = "JS",
		ts = "TS",
		json = "{}",
		md = "M↓",
		sh = "$",
		toml = "T",
		yml = "Y",
		yaml = "Y",
	}

	return icons[extension] or "·"
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

					if depth < 1 and State.expanded[path] == nil then
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
			local arrow = expanded and "▾" or "▸"
			line = indent .. arrow .. " ▣ " .. entry.name .. "/"
		elseif entry.path == State.entry_path then
			line = indent .. "▶ " .. entry.name .. "  ★"
		else
			line = indent .. "  " .. File_Icon(entry.name) .. " " .. entry.name
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

local function Apply_Highlights(lines, items, line_by_path)
	local buf = State.buffer
	vim.api.nvim_buf_clear_namespace(buf, Highlight_Namespace, 0, -1)

	for line_number, line in ipairs(lines) do
		local zero_line = line_number - 1

		if line:find("HYPERMAX", 1, true) then
			vim.api.nvim_buf_add_highlight(buf, Highlight_Namespace, "HyperMaxHeader", zero_line, 0, -1)
		elseif line:find("PROJECT EXPLORER", 1, true) then
			vim.api.nvim_buf_add_highlight(buf, Highlight_Namespace, "HyperMaxSubtitle", zero_line, 0, -1)
		elseif line:match("^  [%u%d ]+$") and line:match("%u") then
			vim.api.nvim_buf_add_highlight(buf, Highlight_Namespace, "HyperMaxSection", zero_line, 0, -1)
		elseif line:match("^  ─") or line:match("^  ═") then
			vim.api.nvim_buf_add_highlight(buf, Highlight_Namespace, "HyperMaxMuted", zero_line, 0, -1)
		end

		local item = items[line_number]
		if item then
			local group = item.path == State.entry_path and "HyperMaxEntry"
				or (item.type == "directory" and "HyperMaxDirectory" or "HyperMaxFile")
			vim.api.nvim_buf_add_highlight(buf, Highlight_Namespace, group, zero_line, 0, -1)
		end

		if line:match("^  [qrf] ") or line:match("^  Enter") then
			vim.api.nvim_buf_add_highlight(buf, Highlight_Namespace, "HyperMaxKey", zero_line, 0, -1)
		end
	end
end

local function Render()
	if not State.buffer or not vim.api.nvim_buf_is_valid(State.buffer) then
		return
	end

	local root = State.root
	local metadata = State.metadata
	local lines, items, line_by_path = {}, {}, {}

	local function Add(text)
		lines[#lines + 1] = text
	end

	Add("  ◆ HYPERMAX")
	Add("  PROJECT EXPLORER")
	Add("  ════════════════════════════════")
	Add("")
	Add("  " .. metadata.name)
	Add("  " .. metadata.language .. "  ·  " .. metadata.manager)
	Add("")

	Add("  ENTRY POINT")
	Add("  ────────────────────────────────")
	if metadata.entry_file ~= "" then
		Add("  ▶ " .. metadata.entry_file)
		Add("  ƒ " .. metadata.entry_function .. "()")
	else
		Add("  Not configured")
		Add("  Set project.entry_point in basics.json")
	end
	Add("")

	Add("  FILES")
	Add("  ────────────────────────────────")

	if #State.tree == 0 then
		Add("  (empty project)")
	else
		Render_Tree(State.tree, 0, lines, items, line_by_path)
	end

	Add("")
	Add("  PROJECT")
	Add("  ────────────────────────────────")
	Add("  Created  " .. Format_Date(metadata.created_at))
	Add("  Git      " .. (metadata.git_enabled and "detected" or "not detected"))
	Add("  Root")
	Add("  " .. root)
	Add("")
	Add("  KEYS")
	Add("  ────────────────────────────────")
	Add("  Enter  Open / toggle folder")
	Add("  r      Refresh tree")
	Add("  q      Close panel")

	local cursor_line = 1
	if State.window and vim.api.nvim_win_is_valid(State.window) then
		cursor_line = vim.api.nvim_win_get_cursor(State.window)[1]
	end

	vim.bo[State.buffer].modifiable = true
	vim.api.nvim_buf_set_lines(State.buffer, 0, -1, false, lines)
	vim.bo[State.buffer].modifiable = false
	vim.bo[State.buffer].modified = false

	State.items = items
	State.line_by_path = line_by_path
	Apply_Highlights(lines, items, line_by_path)

	if State.window and vim.api.nvim_win_is_valid(State.window) then
		vim.api.nvim_win_set_cursor(State.window, {
			math.min(cursor_line, #lines),
			0,
		})
	end
end

-- =========================================================
-- DASHBOARD ACTIONS
-- =========================================================

local function Get_Selected_Item()
	if not State.window or not vim.api.nvim_win_is_valid(State.window) then
		return nil
	end

	local line = vim.api.nvim_win_get_cursor(State.window)[1]
	return State.items and State.items[line]
end

local function Get_Editor_Window()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if win ~= State.window and vim.api.nvim_win_is_valid(win) then
			return win
		end
	end

	-- If the panel is the only window, create an editor window to its right.
	if State.window and vim.api.nvim_win_is_valid(State.window) then
		vim.api.nvim_set_current_win(State.window)
		vim.cmd("rightbelow vsplit")
		return vim.api.nvim_get_current_win()
	end

	return vim.api.nvim_get_current_win()
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
		if new_line and State.window and vim.api.nvim_win_is_valid(State.window) then
			vim.api.nvim_win_set_cursor(State.window, { new_line, 0 })
		end
		return
	end

	if not Is_File(entry.path) then
		Notify("File no longer exists: " .. entry.path, vim.log.levels.WARN)
		return
	end

	-- Open the selected file in the editor window, never in the panel.
	local editor_window = Get_Editor_Window()
	vim.api.nvim_set_current_win(editor_window)
	vim.cmd("edit " .. vim.fn.fnameescape(entry.path))
end

local function Refresh()
	local metadata, err = Get_Project_Metadata(State.root)
	if not metadata then
		Notify(tostring(err), vim.log.levels.ERROR)
		return
	end

	State.metadata = metadata
	State.entry_path = metadata.entry_file ~= "" and Join(State.root, metadata.entry_file) or nil
	State.tree = Build_Tree(State.root, 0, { count = 0 })
	Render()
end

local function Close_Panel()
	if State.window and vim.api.nvim_win_is_valid(State.window) then
		local panel = State.window
		State.window = nil
		pcall(vim.api.nvim_win_close, panel, true)
	end
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

	Map("<CR>", Open_Selected, "HyperMax: open file or toggle folder")
	Map("r", Refresh, "HyperMax: refresh project panel")
	Map("q", Close_Panel, "HyperMax: close project panel")
end

local function Configure_Panel_Window(win)
	vim.api.nvim_win_set_width(win, PANEL_WIDTH)
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].foldcolumn = "0"
	vim.wo[win].wrap = false
	vim.wo[win].cursorline = true
	vim.wo[win].winfixwidth = true
	vim.wo[win].winhl = "Normal:HyperMaxPanel,EndOfBuffer:HyperMaxMuted"
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

	Define_Highlights()

	local existing_window = State.window and vim.api.nvim_win_is_valid(State.window)

	State.root = project_root
	State.metadata = metadata
	State.entry_path = metadata.entry_file ~= "" and Join(project_root, metadata.entry_file) or nil
	State.expanded = {}
	State.tree = Build_Tree(project_root, 0, { count = 0 })

	local buf = State.buffer
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		buf = vim.api.nvim_create_buf(false, true)
		State.buffer = buf
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].bufhidden = "hide"
		vim.bo[buf].swapfile = false
		vim.bo[buf].filetype = "hypermaxdashboard"
		pcall(vim.api.nvim_buf_set_name, buf, "HyperMax://" .. metadata.name)
	end

	if existing_window then
		-- Reuse the panel window if its buffer was deleted or changed.
		vim.api.nvim_set_current_win(State.window)
		vim.api.nvim_win_set_buf(State.window, buf)
	else
		-- Create a real left sidebar. The original editor remains to its right.
		vim.cmd("topleft " .. PANEL_WIDTH .. "vsplit")
		State.window = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(State.window, buf)
	end

	pcall(vim.api.nvim_buf_set_name, buf, "HyperMax://" .. metadata.name)
	Configure_Panel_Window(State.window)
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

function Dashboard.Close()
	Close_Panel()
end

function Dashboard.Get_State()
	return State
end

return Dashboard
