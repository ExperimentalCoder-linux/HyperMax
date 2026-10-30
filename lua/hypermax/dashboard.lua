local Dashboard = {}

local uv = vim.uv or vim.loop
local Project_Config = require("hypermax.project_config")
local Filesystem = require("hypermax.filesystem")
local Git = require("hypermax.git")

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

local function Normalize_Path(path)
	return Filesystem.Normalize(path)
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
	return Filesystem.Safe_Child(State.root, input)
end

local function Git_Command(args)
	return Git.Run(State.root, args)
end

local function Refresh_Git()
	State.git = Git.Snapshot(State.root)
end

local function Git_Marker(path)
	local status = State.git.statuses[Normalize_Path(path)]
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

		local hidden_hmc_backup = name:match("^%.hmc%.backup%-") ~= nil
		if not hidden_hmc_backup and not (kind == "directory" and IGNORED_DIRECTORIES[name]) then
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
	Add("  R      Rename / move selected item")
	Add("  x      Cut item   p  Paste into folder")
	Add("  d      Delete item (confirmation)")
	Add("  s      Cycle sort order")
	Add("  g      Git menu    G  Init Git")
	Add("  m      Workspace  t  Task board  w  Run configurations")
	Add("  f      Find files  /  Search text")
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

-- Refresh the sidebar after terminal-driven Git actions finish. Register this
-- before launching any terminal command so fast exits cannot race the handler.
local Git_Terminal_Augroup = vim.api.nvim_create_augroup("HyperMaxDashboardGitRefresh", { clear = true })
vim.api.nvim_create_autocmd("TermClose", {
	group = Git_Terminal_Augroup,
	callback = function()
		vim.schedule(function()
			if State.root and State.root ~= "" then Refresh() end
		end)
	end,
})

local function Reveal_Created_Path(kind, path)
	local root = Normalize_Path(State.root)
	local cursor = kind == "folder" and Normalize_Path(path) or Normalize_Path(vim.fn.fnamemodify(path, ":h"))
	while cursor and cursor ~= root and Filesystem.Is_Within(root, cursor) do
		State.expanded[cursor] = true
		local parent = Normalize_Path(vim.fn.fnamemodify(cursor, ":h"))
		if not parent or parent == cursor then break end
		cursor = parent
	end
	Refresh()
	local line = State.line_by_path[Normalize_Path(path)]
	if line and State.window and vim.api.nvim_win_is_valid(State.window) then
		vim.api.nvim_win_set_cursor(State.window, { line, 0 })
	end
end

local function Cycle_Sort()
	State.sort_mode = (State.sort_mode % #SORT_MODES) + 1
	Refresh()
	Notify("Sorting by " .. SORT_MODES[State.sort_mode])
end

local function Create_Item(kind)
	local label = kind == "file" and "New file path (relative to project):" or "New folder path (relative to project):"
	local input_ok, input_error = pcall(vim.ui.input, { prompt = label }, function(input)
		local call_ok, created, path_or_error, detail = pcall(Filesystem.Create, State.root, kind, input)
		if not call_ok then
			Notify("Could not create " .. kind .. ": " .. tostring(created), vim.log.levels.ERROR)
			return
		end
		if not created then
			local failure = path_or_error or detail
			if failure and failure ~= "cancelled" then
				Notify(tostring(failure), vim.log.levels.ERROR)
			end
			return
		end
		local created_path = path_or_error
		Reveal_Created_Path(kind, created_path)
		Notify((kind == "file" and "Created file: " or "Created folder: ") .. tostring(input))
	end)
	if not input_ok then
		Notify("Could not open input prompt: " .. tostring(input_error), vim.log.levels.ERROR)
	end
end

local function Relative_Path(path)
	local root = Normalize_Path(State.root)
	local full = Normalize_Path(path)
	if not root or not full or not Filesystem.Is_Within(root, full) then return nil end
	return full:sub(#root + 2)
end

local function Rename_Selected()
	local entry = Get_Selected_Item()
	if not entry then Notify("Select a file or folder first", vim.log.levels.WARN); return end
	local old_relative = Relative_Path(entry.path)
	if not old_relative then Notify("Selected path is outside the project", vim.log.levels.ERROR); return end
	vim.ui.input({ prompt = "Rename / move to project-relative path:", default = old_relative }, function(input)
		if not input or vim.trim(input) == "" then return end
		local ok, destination, err = Filesystem.Move(State.root, old_relative, input)
		if not ok then Notify("Rename/move failed: " .. tostring(err), vim.log.levels.ERROR); return end
		if entry.type == "directory" then State.expanded[entry.path] = nil; State.expanded[destination] = true end
		Reveal_Created_Path(entry.type == "directory" and "folder" or "file", destination)
		Notify("Moved to " .. tostring(input))
	end)
end

local function Cut_Selected()
	local entry = Get_Selected_Item()
	if not entry then Notify("Select a file or folder first", vim.log.levels.WARN); return end
	local relative = Relative_Path(entry.path)
	if not relative then Notify("Selected path is outside the project", vim.log.levels.ERROR); return end
	State.cut_path = relative
	Notify("Cut: " .. relative .. " — navigate to a destination and press p")
end

local function Paste_Cut()
	if not State.cut_path then Notify("Nothing has been cut", vim.log.levels.WARN); return end
	local source = State.cut_path
	local name = source:match("([^/]+)$")
	vim.ui.input({ prompt = "Destination folder (relative; empty = project root):", default = "" }, function(input)
		if input == nil then return end
		input = vim.trim(input)
		local destination_directory = State.root
		if input ~= "" then
			local full, path_error = Filesystem.Safe_Child(State.root, input)
			if not full then Notify(tostring(path_error), vim.log.levels.ERROR); return end
			local stat = uv.fs_stat(full)
			if not stat or stat.type ~= "directory" then Notify("Destination is not an existing folder: " .. input, vim.log.levels.ERROR); return end
			destination_directory = full
		end
		local target = destination_directory == State.root and name or (input .. "/" .. name)
		local ok, destination, err = Filesystem.Move(State.root, source, target)
		if not ok then Notify("Paste failed: " .. tostring(err), vim.log.levels.ERROR); return end
		State.cut_path = nil
		Reveal_Created_Path(Is_Directory(destination) and "folder" or "file", destination)
		Notify("Moved to " .. target)
	end)
end

local function Delete_Selected()
	local entry = Get_Selected_Item()
	if not entry then Notify("Select a file or folder first", vim.log.levels.WARN); return end
	local relative = Relative_Path(entry.path)
	if not relative then Notify("Selected path is outside the project", vim.log.levels.ERROR); return end
	vim.ui.select({ "Delete permanently", "Cancel" }, { prompt = "Delete " .. relative .. "?" }, function(choice)
		if choice ~= "Delete permanently" then return end
		local ok, err = Filesystem.Delete(State.root, relative)
		if not ok then Notify("Delete failed: " .. tostring(err), vim.log.levels.ERROR); return end
		if State.cut_path == relative or (State.cut_path and State.cut_path:sub(1, #relative + 1) == relative .. "/") then State.cut_path = nil end
		State.expanded[entry.path] = nil
		Refresh()
		Notify("Deleted " .. relative)
	end)
end

local Initialize_Git

local function Run_Git_Terminal(action)
	local editor_window = Get_Editor_Window()
	vim.api.nvim_set_current_win(editor_window)
	vim.cmd("botright 12split")
	vim.cmd("terminal git -C " .. vim.fn.shellescape(State.root) .. " " .. action)
end

local function Show_Git_Output(title, lines)
	local buffer = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buffer, "HyperMaxGit://" .. title .. "-" .. tostring(buffer))
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, (#lines > 0 and lines or { "(no output)" }))
	vim.bo[buffer].buftype = "nofile"
	vim.bo[buffer].bufhidden = "wipe"
	vim.bo[buffer].swapfile = false
	vim.bo[buffer].modifiable = false
	vim.cmd("botright 12split")
	vim.api.nvim_win_set_buf(0, buffer)
	vim.api.nvim_win_set_option(0, "wrap", false)
end

local function Report_Git_Result(label, output, err)
	if not output then
		Notify(label .. " failed: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end
	Notify(label .. " completed")
	Refresh()
	return true
end

local function Select_Git_Entry(items, prompt, callback)
	if not items or #items == 0 then
		Notify("No " .. prompt:lower() .. " found")
		return
	end
	vim.ui.select(items, { prompt = prompt }, callback)
end

local function Show_Branch_Menu()
	vim.ui.select({ "Switch branch", "Create branch", "Delete local branch", "List local and remote branches", "Cancel" }, {
		prompt = "Git branches",
	}, function(action)
		if not action or action == "Cancel" then return end
		if action == "Create branch" then
			vim.ui.input({ prompt = "New branch name: " }, function(name)
				if not name or vim.trim(name) == "" then return end
				local output, err = Git.Create_Branch(State.root, vim.trim(name))
				Report_Git_Result("Create branch", output, err)
			end)
		elseif action == "List local and remote branches" then
			local items, err = Git.Branches(State.root, true)
			if not items then Notify("Could not list branches: " .. tostring(err), vim.log.levels.ERROR); return end
			Show_Git_Output("Branches", items)
		elseif action == "Switch branch" or action == "Delete local branch" then
			local items, err = Git.Branches(State.root, false)
			if not items then Notify("Could not list branches: " .. tostring(err), vim.log.levels.ERROR); return end
			Select_Git_Entry(items, action == "Switch branch" and "Switch to branch" or "Delete branch", function(branch)
				if not branch then return end
				if action == "Switch branch" then
					local output, switch_error = Git.Switch_Branch(State.root, branch)
					Report_Git_Result("Switch branch", output, switch_error)
				else
					vim.ui.select({ "Delete branch", "Cancel" }, { prompt = "Delete local branch '" .. branch .. "'?" }, function(confirm)
						if confirm ~= "Delete branch" then return end
						local output, delete_error = Git.Delete_Branch(State.root, branch, false)
						Report_Git_Result("Delete branch", output, delete_error)
					end)
				end
			end)
		end
	end)
end

local function Show_Remote_Menu()
	local actions = { "List remote URLs", "Add remote", "Remove remote", "Open remote details in terminal", "Cancel" }
	vim.ui.select(actions, { prompt = "Git remotes" }, function(action)
		if not action or action == "Cancel" then return end
		if action == "List remote URLs" then
			local output, err = Git.Remote_Details(State.root)
			if not output then Notify("Could not list remotes: " .. tostring(err), vim.log.levels.ERROR) else Show_Git_Output("Remotes", output) end
		elseif action == "Open remote details in terminal" then
			Run_Git_Terminal("remote -v")
		elseif action == "Add remote" then
			vim.ui.input({ prompt = "Remote name (for example origin): " }, function(name)
				if not name or vim.trim(name) == "" then return end
				vim.ui.input({ prompt = "Remote URL: " }, function(url)
					if not url or vim.trim(url) == "" then return end
					local output, err = Git.Add_Remote(State.root, vim.trim(name), vim.trim(url))
					Report_Git_Result("Add remote", output, err)
				end)
			end)
		elseif action == "Remove remote" then
			local remotes, err = Git.Remotes(State.root)
			if not remotes then Notify("Could not list remotes: " .. tostring(err), vim.log.levels.ERROR); return end
			Select_Git_Entry(remotes, "Remove remote", function(name)
				if not name then return end
				vim.ui.select({ "Remove remote", "Cancel" }, { prompt = "Remove remote '" .. name .. "'?" }, function(confirm)
					if confirm ~= "Remove remote" then return end
					local output, remove_error = Git.Remove_Remote(State.root, name)
					Report_Git_Result("Remove remote", output, remove_error)
				end)
			end)
		end
	end)
end

local function Show_Stash_Menu()
	vim.ui.select({ "Create stash", "Apply stash", "Pop stash", "List stashes", "Cancel" }, {
		prompt = "Git stash",
	}, function(action)
		if not action or action == "Cancel" then return end
		if action == "Create stash" then
			vim.ui.input({ prompt = "Stash message (optional): " }, function(message)
				local output, err = Git.Stash(State.root, message or "")
				Report_Git_Result("Create stash", output, err)
			end)
		else
			local stashes, err = Git.Stashes(State.root)
			if not stashes then Notify("Could not list stashes: " .. tostring(err), vim.log.levels.ERROR); return end
			if action == "List stashes" then Show_Git_Output("Stashes", stashes); return end
			Select_Git_Entry(stashes, action, function(stash)
				if not stash then return end
				local reference = stash:match("^(%S+)")
				local output, stash_error
				if action == "Apply stash" then output, stash_error = Git.Stash_Apply(State.root, reference)
				else output, stash_error = Git.Stash_Pop(State.root, reference) end
				Report_Git_Result(action, output, stash_error)
			end)
		end
	end)
end

local function Show_Tag_Menu()
	vim.ui.select({ "View tag", "Create tag", "Delete tag", "List tags", "Cancel" }, { prompt = "Git tags" }, function(action)
		if not action or action == "Cancel" then return end
		local tags, err = Git.Tags(State.root)
		if not tags then Notify("Could not list tags: " .. tostring(err), vim.log.levels.ERROR); return end
		if action == "List tags" then Show_Git_Output("Tags", tags); return end
		if action == "Create tag" then
			vim.ui.input({ prompt = "New tag name: " }, function(tag)
				if not tag or vim.trim(tag) == "" then return end
				vim.ui.input({ prompt = "Annotation message (leave empty for lightweight tag): " }, function(message)
					local output, tag_error = Git.Create_Tag(State.root, vim.trim(tag), message or "")
					Report_Git_Result("Create tag", output, tag_error)
				end)
			end)
			return
		end
		Select_Git_Entry(tags, action == "Delete tag" and "Delete tag" or "View tag", function(tag)
			if not tag then return end
			if action == "Delete tag" then
				vim.ui.select({ "Delete tag", "Cancel" }, { prompt = "Delete tag '" .. tag .. "'?" }, function(confirm)
					if confirm ~= "Delete tag" then return end
					local output, delete_error = Git.Delete_Tag(State.root, tag)
					Report_Git_Result("Delete tag", output, delete_error)
				end)
			else
				local output, show_error = Git.Run(State.root, { "--no-pager", "show", "--stat", "--no-renames", tag })
				if not output then Notify("Could not show tag: " .. tostring(show_error), vim.log.levels.ERROR) else Show_Git_Output("Tag " .. tag, output) end
			end
		end)
	end)
end

local function Show_Git_Menu()
	Refresh_Git()
	local choices = State.git.available and {
		"Status", "Stage all changes", "Stage selected file", "Unstage selected file",
		"Commit staged changes", "Fetch", "Pull", "Push", "Branches", "Remotes",
		"Tags", "Stash", "Diff summary", "Recent commits", "Initialize repository",
	} or { "Initialize repository", "Cancel" }

	vim.ui.select(choices, { prompt = "HyperMax Git" }, function(choice)
		if not choice or choice == "Cancel" then return end
		if choice == "Initialize repository" then
			Initialize_Git()
		elseif choice == "Status" then
			local lines, err = Git_Command({ "status", "--short", "--branch" })
			if lines then Show_Git_Output("Status", lines) else Notify("Git status failed: " .. tostring(err), vim.log.levels.ERROR) end
		elseif choice == "Stage all changes" then
			local output, err = Git.Add_All(State.root)
			Report_Git_Result("Stage all changes", output, err)
		elseif choice == "Stage selected file" or choice == "Unstage selected file" then
			local selected = Get_Selected_Item()
			if not selected then Notify("Select a file in the dashboard first", vim.log.levels.WARN); return end
			local relative = Relative_Path(selected.path)
			if not relative then Notify("Selected path is outside the project", vim.log.levels.ERROR); return end
			local output, err
			if choice == "Stage selected file" then output, err = Git.Stage(State.root, relative)
			else output, err = Git.Unstage(State.root, relative) end
			Report_Git_Result(choice, output, err)
		elseif choice == "Commit staged changes" then
			vim.ui.input({ prompt = "Commit message: " }, function(message)
				if not message or vim.trim(message) == "" then return end
				local output, err = Git.Commit(State.root, message)
				Report_Git_Result("Commit", output, err)
			end)
		elseif choice == "Fetch" then Run_Git_Terminal("fetch --all --prune")
		elseif choice == "Pull" then Run_Git_Terminal("pull")
		elseif choice == "Push" then Run_Git_Terminal("push")
		elseif choice == "Branches" then Show_Branch_Menu()
		elseif choice == "Remotes" then Show_Remote_Menu()
		elseif choice == "Tags" then Show_Tag_Menu()
		elseif choice == "Stash" then Show_Stash_Menu()
		elseif choice == "Diff summary" then
			local unstaged, err = Git.Diff(State.root, false)
			if not unstaged then Notify("Git diff failed: " .. tostring(err), vim.log.levels.ERROR); return end
			local staged, staged_err = Git.Diff(State.root, true)
			if not staged then Notify("Git staged diff failed: " .. tostring(staged_err), vim.log.levels.ERROR); return end
			local lines = { "Unstaged changes:", "" }
			vim.list_extend(lines, unstaged)
			vim.list_extend(lines, { "", "Staged changes:", "" })
			vim.list_extend(lines, staged)
			Show_Git_Output("Diff summary", lines)
		elseif choice == "Recent commits" then
			local lines, err = Git.Log(State.root, 20)
			if lines then Show_Git_Output("Recent commits", lines) else Notify("Git log failed: " .. tostring(err), vim.log.levels.ERROR) end
		end
	end)
end

Initialize_Git = function()
	if State.git.available then
		Notify("Git is already initialized on branch " .. (State.git.branch or "?"))
		return true
	end
	local output, err = Git_Command({ "init" })
	if not output then
		Notify("Git init failed: " .. tostring(err), vim.log.levels.ERROR)
		return false, err
	end
	Refresh()
	Notify("Initialized Git repository")
	return true
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
	Map("R", Rename_Selected, "HyperMax: rename or move selected item")
	Map("x", Cut_Selected, "HyperMax: cut selected file or folder")
	Map("p", Paste_Cut, "HyperMax: paste cut file or folder")
	Map("d", Delete_Selected, "HyperMax: delete selected file or folder")
	Map("s", Cycle_Sort, "HyperMax: cycle file sorting")
	Map("g", Show_Git_Menu, "HyperMax: Git actions")
	Map("G", Initialize_Git, "HyperMax: initialize Git")
	Map("m", function() require("hypermax.workspace").Open(State.root) end, "HyperMax: open workspace home")
	Map("t", function() require("hypermax.flow").Open_Tasks(State.root) end, "HyperMax: open task board")
	Map("w", function() require("hypermax.flow").Open_Runners(State.root) end, "HyperMax: open run configurations")
	Map("f", function() require("hypermax.workspace").Find_Files(State.root) end, "HyperMax: find project files")
	Map("/", function() require("hypermax.workspace").Search_Text(State.root) end, "HyperMax: search project text")
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

	local registered, register_error = Project_Config.Mark_Project_Opened(project_root)
	if not registered then
		Notify("Project opened, but recent-project history could not be updated: " .. tostring(register_error), vim.log.levels.WARN)
	end

	Define_Highlights()

	local existing_window = State.window and vim.api.nvim_win_is_valid(State.window)
	if Normalize_Path(State.root or "") ~= Normalize_Path(project_root) then
		State.cut_path = nil
	end

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

function Dashboard.Convert_Folder(root)
	root = vim.fn.fnamemodify(vim.fn.expand(root or vim.fn.getcwd()), ":p")
	local ok, result = Project_Config.Convert_Folder(root, { name = vim.fs.basename(root) })
	if not ok then return false, result end
	State.cut_path = nil
	Dashboard.Open(root)
	return true, result
end

function Dashboard.Undo_Conversion(root)
	root = Dashboard.Find_Project_Root(root or vim.fn.getcwd()) or vim.fn.fnamemodify(root or vim.fn.getcwd(), ":p")
	local ok, result = Project_Config.Undo_Conversion(root)
	if ok and State.root == root then Close_Panel() end
	return ok, result
end

function Dashboard.Scrape(root)
	root = Dashboard.Find_Project_Root(root or vim.fn.getcwd()) or vim.fn.fnamemodify(root or vim.fn.getcwd(), ":p")
	local ok, result = Project_Config.Scrape(root)
	if ok and State.root == root then Close_Panel() end
	return ok, result
end

function Dashboard.Refresh()
	Refresh()
end

function Dashboard.Create(kind, input)
	local ok, path, err = Filesystem.Create(State.root, kind, input)
	if ok then Reveal_Created_Path(kind, path) end
	return ok, path, err
end

function Dashboard.Initialize_Git()
	return Initialize_Git()
end

function Dashboard.Cycle_Sort()
	Cycle_Sort()
	return SORT_MODES[State.sort_mode]
end

function Dashboard.Close()
	Close_Panel()
end

function Dashboard.Get_State()
	return State
end

return Dashboard
