local Dashboard = {}

local uv = vim.uv or vim.loop
local Project_Config = require("hypermax.project_config")

local MAX_TREE_ENTRIES = 200
local MAX_TREE_DEPTH = 5
local PANEL_WIDTH = 38
local SORT_MODES = { "alphabetical", "file type", "modified", "created" }

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
	git = { available = false, branch = nil, statuses = {} },
	sort_mode = 1,
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

local function Safe_Child_Path(input)
	input = vim.trim(input or ""):gsub("\\", "/")
	if input == "" or input:sub(1, 1) == "/" or input:match("^%a:") then
		return nil, "Enter a non-empty relative path"
	end
	for part in input:gmatch("[^/]+") do
		if part == ".." or part == "." then
			return nil, "Relative paths cannot contain . or .."
		end
	end
	local full = vim.fs.normalize(Join(State.root, input))
	local root = vim.fs.normalize(State.root)
	if full:sub(1, #root + 1) ~= root .. "/" then
		return nil, "Path must stay inside the project"
	end
	return full
end

local function Git_Command(args)
	if vim.fn.executable("git") ~= 1 then
		return nil, "Git is not installed or not on PATH"
	end
	local command = { "git", "-C", State.root }
	vim.list_extend(command, args)
	local output = vim.fn.systemlist(command)
	if vim.v.shell_error ~= 0 then
		return nil, table.concat(output, "\n")
	end
	return output
end

local function Refresh_Git()
	State.git = { available = false, branch = nil, statuses = {} }
	local branch = Git_Command({ "rev-parse", "--abbrev-ref", "HEAD" })
	if not branch then
		return
	end
	local statuses = Git_Command({ "status", "--porcelain=v1", "--untracked-files=all" }) or {}
	State.git.available = true
	State.git.branch = branch[1] or "HEAD"
	for _, row in ipairs(statuses) do
		local code = row:sub(1, 2)
		local path = row:sub(4)
		if path:find(" -> ", 1, true) then
			path = path:match(" -> (.+)$") or path
		end
		State.git.statuses[vim.fs.normalize(Join(State.root, path))] = code
	end
end

local function Git_Marker(path)
	local status = State.git.statuses[vim.fs.normalize(path)]
	if not status then return " " end
	if status == "??" then return "?" end
	if status:find("A", 1, true) then return "+" end
	if status:find("D", 1, true) then return "−" end
	if status:find("R", 1, true) then return "»" end
	if status:find("M", 1, true) then return "●" end
	return "•"
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
				local stat = uv.fs_stat(path) or {}
				local entry = {
					name = name,
					path = path,
					type = kind,
					modified = stat.mtime and stat.mtime.sec or 0,
					created = stat.birthtime and stat.birthtime.sec or (stat.ctime and stat.ctime.sec or 0),
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

		local mode = SORT_MODES[State.sort_mode] or "alphabetical"
		if mode == "file type" then
			local a_ext = a.name:match("%.([^%.]+)$") or ""
			local b_ext = b.name:match("%.([^%.]+)$") or ""
			if a_ext:lower() ~= b_ext:lower() then
				return a_ext:lower() < b_ext:lower()
			end
		elseif mode == "modified" and a.modified ~= b.modified then
			return a.modified > b.modified
		elseif mode == "created" and a.created ~= b.created then
			return a.created > b.created
		end
		return a.name:lower() < b.name:lower()
	end)

	return entries
end

local function Render_Tree(entries, depth, lines, items, line_by_path)
	local indent = string.rep("  ", depth)

	for _, entry in ipairs(entries) do
		local line

		local marker = Git_Marker(entry.path)
		if entry.type == "directory" then
			local expanded = State.expanded[entry.path] == true
			local arrow = expanded and "▾" or "▸"
			line = indent .. arrow .. " ▣ " .. entry.name .. "/ " .. marker
		elseif entry.path == State.entry_path then
			line = indent .. "▶ " .. File_Icon(entry.name) .. " " .. entry.name .. " ★ " .. marker
		else
			line = indent .. "  " .. File_Icon(entry.name) .. " " .. entry.name .. " " .. marker
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

	Add("  FILES  ·  " .. SORT_MODES[State.sort_mode])
	Add("  ────────────────────────────────────")

	if #State.tree == 0 then
		Add("  (empty project)")
	else
		Render_Tree(State.tree, 0, lines, items, line_by_path)
	end

	Add("")
	Add("  PROJECT")
	Add("  ────────────────────────────────")
	Add("  Created  " .. Format_Date(metadata.created_at))
	Add("  Git      " .. (State.git.available and ("branch " .. (State.git.branch or "?")) or "not initialized"))
	Add("  Changes  " .. tostring(vim.tbl_count(State.git.statuses)) .. " files")
	Add("  Root")
	Add("  " .. root)
	Add("")
	Add("  KEYS")
	Add("  ────────────────────────────────")
	Add("  Enter  Open / toggle folder")
	Add("  a      New file   A  New folder")
	Add("  s      Cycle sort order")
	Add("  g      Git menu    G  Init Git")
	Add("  ? + -  Git markers: modified/untracked/added")
	Add("  r      Refresh   q  Close panel")

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
	Refresh_Git()
	State.tree = Build_Tree(State.root, 0, { count = 0 })
	Render()
end

local function Cycle_Sort()
	State.sort_mode = (State.sort_mode % #SORT_MODES) + 1
	Refresh()
	Notify("Sorting by " .. SORT_MODES[State.sort_mode])
end

local function Create_Item(kind)
	local label = kind == "file" and "New file path (relative to project):" or "New folder path (relative to project):"
	vim.ui.input({ prompt = label }, function(input)
		if not input or vim.trim(input) == "" then return end
		local path, err = Safe_Child_Path(input)
		if not path then
			Notify(err, vim.log.levels.ERROR)
			return
		end
		if uv.fs_lstat(path) then
			Notify("Already exists: " .. input, vim.log.levels.WARN)
			return
		end
		local parent = vim.fn.fnamemodify(path, ":h")
		if parent ~= State.root and vim.fn.mkdir(parent, "p") == 0 and not Is_Directory(parent) then
			Notify("Could not create parent directory: " .. parent, vim.log.levels.ERROR)
			return
		end
		if kind == "folder" then
			if vim.fn.mkdir(path, "p") == 0 and not Is_Directory(path) then
				Notify("Could not create folder: " .. input, vim.log.levels.ERROR)
				return
			end
			State.expanded[parent] = true
			State.expanded[path] = true
		else
			local fd, open_err = uv.fs_open(path, "wx", 420)
			if not fd then
				Notify("Could not create file: " .. tostring(open_err), vim.log.levels.ERROR)
				return
			end
			uv.fs_close(fd)
			State.expanded[parent] = true
		end
		Refresh()
		local line = State.line_by_path[vim.fs.normalize(path)]
		if line and State.window and vim.api.nvim_win_is_valid(State.window) then
			vim.api.nvim_win_set_cursor(State.window, { line, 0 })
		end
		Notify((kind == "file" and "Created file: " or "Created folder: ") .. input)
	end)
end

local Initialize_Git

local function Run_Git_Terminal(action)
	local editor_window = Get_Editor_Window()
	vim.api.nvim_set_current_win(editor_window)
	vim.cmd("botright 12split")
	vim.cmd("terminal git -C " .. vim.fn.shellescape(State.root) .. " " .. action)
end

local function Show_Git_Menu()
	Refresh_Git()
	local choices = State.git.available
		and { "Status", "Stage all changes", "Commit staged changes", "Push", "Pull", "Recent commits", "Initialize repository" }
		or { "Initialize repository", "Cancel" }

	vim.ui.select(choices, { prompt = "HyperMax Git" }, function(choice)
		if not choice or choice == "Cancel" then return end
		if choice == "Initialize repository" then
			Initialize_Git()
		elseif choice == "Status" then
			local lines, err = Git_Command({ "status", "--short", "--branch" })
			if lines then Notify(table.concat(lines, " | ")) else Notify("Git status failed: " .. tostring(err), vim.log.levels.ERROR) end
			Refresh()
		elseif choice == "Stage all changes" then
			local output, err = Git_Command({ "add", "-A" })
			if not output then Notify("Git add failed: " .. tostring(err), vim.log.levels.ERROR) else Notify("Staged all project changes") end
			Refresh()
		elseif choice == "Commit staged changes" then
			vim.ui.input({ prompt = "Commit message: " }, function(message)
				if not message or vim.trim(message) == "" then return end
				local output, err = Git_Command({ "commit", "-m", message })
				if not output then Notify("Git commit failed: " .. tostring(err), vim.log.levels.ERROR) else Notify(table.concat(output, " | ")) end
				Refresh()
			end)
		elseif choice == "Push" then
			Run_Git_Terminal("push")
		elseif choice == "Pull" then
			Run_Git_Terminal("pull")
		elseif choice == "Recent commits" then
			local lines = Git_Command({ "--no-pager", "log", "-5", "--oneline", "--decorate" })
			Notify(lines and table.concat(lines, " | ") or "No commits yet")
		end
	end)
end

Initialize_Git = function()
	if State.git.available then
		Notify("Git is already initialized on branch " .. (State.git.branch or "?"))
		return
	end
	local output, err = Git_Command({ "init" })
	if not output then
		Notify("Git init failed: " .. tostring(err), vim.log.levels.ERROR)
		return
	end
	Refresh()
	Notify("Initialized Git repository")
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
	Map("a", function() Create_Item("file") end, "HyperMax: create file")
	Map("A", function() Create_Item("folder") end, "HyperMax: create folder")
	Map("s", Cycle_Sort, "HyperMax: cycle file sorting")
	Map("g", Show_Git_Menu, "HyperMax: Git actions")
	Map("G", Initialize_Git, "HyperMax: initialize Git")
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
	State.sort_mode = State.sort_mode or 1
	Refresh_Git()
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
