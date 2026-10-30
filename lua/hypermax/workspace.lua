-- HyperMax workspace home, command palette, project search and navigation.
local Workspace = {}

local Flow = require("hypermax.flow")
local Git = require("hypermax.git")
local Project_Config = require("hypermax.project_config")
local Diagnostics = require("hypermax.diagnostics")
local Window = require("hypermax.window")

local State = { buffer = nil, window = nil, root = nil, recent_projects = {}, recent_project_lines = {} }

local function Notify(message, level)
	vim.notify("HyperMax: " .. message, level or vim.log.levels.INFO)
end

local function Join(...)
	return table.concat({ ... }, "/"):gsub("/+", "/")
end

local function Normalize(path)
	if not path or path == "" then
		local current_buffer = vim.api.nvim_buf_get_name(0)
		path = current_buffer ~= "" and current_buffer or vim.fn.getcwd()
	end
	local absolute = vim.fn.fnamemodify(vim.fn.expand(path), ":p"):gsub("\\", "/")
	if absolute == "/" or absolute:match("^%a:/$") then return absolute end
	return absolute:gsub("/+$", "")
end

local function Find_Project_Root(path)
	path = Normalize(path)
	if vim.fn.filereadable(path) == 1 then path = vim.fn.fnamemodify(path, ":h") end
	while path and path ~= "" do
		if Project_Config.Exists(path) then return path end
		local parent = vim.fn.fnamemodify(path, ":h")
		if parent == path then break end
		path = parent
	end
	return nil
end

local function Close()
	if State.window and vim.api.nvim_win_is_valid(State.window) then
		local win = State.window
		State.window = nil
		pcall(vim.api.nvim_win_close, win, true)
	end
end

local function Open_Window()
	Close()
	local width = math.max(24, math.min(108, vim.o.columns - 4))
	local height = math.min(28, math.max(12, vim.o.lines - 6))
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "hypermaxworkspace"
	local win = Window.Open_Float(buf, "HYPERMAX  /  WORKSPACE", width, height, State.root)
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].wrap = false
	vim.wo[win].cursorline = true
	vim.wo[win].winhl = "Normal:NormalFloat,FloatBorder:FloatBorder,CursorLine:CursorLine"
	State.buffer, State.window = buf, win
	return buf
end

local function Set_Lines(lines)
	if not State.buffer or not vim.api.nvim_buf_is_valid(State.buffer) then return end
	vim.api.nvim_set_hl(0, "HyperMaxWorkspaceTitle", { link = "Title", default = true })
	vim.api.nvim_set_hl(0, "HyperMaxWorkspaceSection", { link = "Special", default = true })
	vim.api.nvim_set_hl(0, "HyperMaxWorkspaceMuted", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "HyperMaxWorkspaceKey", { link = "DiagnosticInfo", default = true })
	vim.bo[State.buffer].modifiable = true
	vim.api.nvim_buf_set_lines(State.buffer, 0, -1, false, lines)
	vim.bo[State.buffer].modifiable = false
	vim.bo[State.buffer].modified = false
	local namespace = vim.api.nvim_create_namespace("HyperMaxWorkspaceHighlights")
	vim.api.nvim_buf_clear_namespace(State.buffer, namespace, 0, -1)
	for index, line in ipairs(lines) do
		local group
		if index == 1 then group = "HyperMaxWorkspaceTitle"
		elseif line:match("^  PROJECT") or line:match("^  WORKSPACE$") or line:match("^  CUSTOMIZE$") then group = "HyperMaxWorkspaceSection"
		elseif line:match("^  %-+") or line:match("^  ◆") then group = "HyperMaxWorkspaceMuted"
		elseif line:match("^%s+[a-zA-Z/ ]+%s+") then group = "HyperMaxWorkspaceKey" end
		if group then vim.api.nvim_buf_add_highlight(State.buffer, namespace, group, index - 1, 0, -1) end
	end
end

local function Map(key, callback, description)
	vim.keymap.set("n", key, callback, { buffer = State.buffer, silent = true, nowait = true, desc = description })
end

local function Focus_Editor_Window()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_is_valid(win) and win ~= State.window then
			local config = vim.api.nvim_win_get_config(win)
			if not config.relative or config.relative == "" then
				vim.api.nvim_set_current_win(win)
				return true
			end
		end
	end
	return false
end

local function Ensure_Editor_Window()
	local focused = Focus_Editor_Window()
	-- A dashboard floating over a terminal, edited file or quickfix list is
	-- confusing. Close the home screen as part of every navigation transition.
	Close()
	if focused then return true end
	local current = vim.api.nvim_get_current_win()
	if not current or not vim.api.nvim_win_is_valid(current) then return false end
	local config = vim.api.nvim_win_get_config(current)
	return not config.relative or config.relative == ""
end

function Workspace.Git_Status(root)
	root = Find_Project_Root(root) or Normalize(root)
	if vim.fn.executable("git") ~= 1 then Notify("Git is not installed", vim.log.levels.WARN); return false end
	if not Ensure_Editor_Window() then Notify("Could not find an editor window for Git status", vim.log.levels.ERROR); return false end
	vim.cmd("botright 12new")
	vim.fn.termopen({ "git", "-C", root, "status", "--short", "--branch" }, { cwd = root })
	vim.cmd("startinsert")
	return true
end

local function Fallback_Find(root)
	local results, count = {}, 0
	local ignored = { [".git"] = true, [".hmc"] = true, ["node_modules"] = true, ["vendor"] = true, ["build"] = true, ["dist"] = true, ["target"] = true }
	local function walk(directory, depth)
		if depth > 12 or count >= 3000 then return end
		local scanner = (vim.uv or vim.loop).fs_scandir(directory)
		if not scanner then return end
		while count < 3000 do
			local name, kind = (vim.uv or vim.loop).fs_scandir_next(scanner)
			if not name then break end
			if not ignored[name] then
				local path = Join(directory, name)
				if kind == "directory" then walk(path, depth + 1)
				elseif kind == "file" then
					results[#results + 1] = path:sub(#root + 2)
					count = count + 1
				end
			end
		end
	end
	walk(root, 0)
	table.sort(results)
	return results
end

function Workspace.Find_Files(root)
	root = Find_Project_Root(root) or Normalize(root)
	local files
	if vim.fn.executable("rg") == 1 then
		files = vim.fn.systemlist({ "rg", "--files", "--hidden", "--glob", "!.git/**", "--glob", "!.hmc/**", root })
		if vim.v.shell_error ~= 0 and #files == 0 then files = {} end
		for index, path in ipairs(files) do
			if path:sub(1, #root + 1) == root .. "/" then files[index] = path:sub(#root + 2) end
		end
	else
		files = Fallback_Find(root)
	end
	if #files == 0 then Notify("No files found in " .. root, vim.log.levels.WARN); return end
	vim.ui.select(files, { prompt = "Find file in " .. vim.fs.basename(root) }, function(choice)
		if not choice then return end
		if not Ensure_Editor_Window() then Notify("Could not find an editor window", vim.log.levels.ERROR); return end
		local path = Join(root, choice)
		vim.cmd("edit " .. vim.fn.fnameescape(path))
	end)
end

function Workspace.Scan_Todos(root)
	root = Find_Project_Root(root) or Normalize(root)
	if vim.fn.executable("rg") ~= 1 then
		Notify("TODO scanning requires ripgrep (rg)", vim.log.levels.WARN)
		return false
	end
	local output = vim.fn.systemlist({
		"rg", "--vimgrep", "--hidden", "--glob", "!.git/**", "--glob", "!.hmc/**",
		"--", "\\b(TODO|FIXME|BUG|HACK)\\b", root,
	})
	local items = {}
	for _, line in ipairs(output) do
		local path, row, col, text = line:match("^(.*):(%d+):(%d+):(.*)$")
		if path and row and col then
			items[#items + 1] = { filename = path, lnum = tonumber(row), col = tonumber(col), text = text }
		end
	end
	if #items == 0 then
		Notify("No TODO, FIXME, BUG or HACK markers found", vim.log.levels.INFO)
		return true
	end
	vim.fn.setqflist({}, " ", { title = "HyperMax project markers", items = items })
	if not Ensure_Editor_Window() then Notify("Could not open the quickfix list", vim.log.levels.ERROR); return false end
	vim.cmd("copen")
	return true
end

function Workspace.Search_Text(root, query)
	root = Find_Project_Root(root) or Normalize(root)
	if not query or vim.trim(query) == "" then
		vim.ui.input({ prompt = "Search project text: " }, function(value)
			if value and value ~= "" then Workspace.Search_Text(root, value) end
		end)
		return
	end
	if vim.fn.executable("rg") ~= 1 then
		Notify("Text search requires ripgrep (rg). File finding still works without it.", vim.log.levels.WARN)
		return false
	end
	local output = vim.fn.systemlist({ "rg", "--vimgrep", "--hidden", "--glob", "!.git/**", "--glob", "!.hmc/**", "--", query, root })
	local items = {}
	for _, line in ipairs(output) do
		local path, row, col, text = line:match("^(.*):(%d+):(%d+):(.*)$")
		if path and row and col then
			items[#items + 1] = { filename = path, lnum = tonumber(row), col = tonumber(col), text = text }
		end
	end
	if #items == 0 then
		Notify("No matches for: " .. query, vim.log.levels.INFO)
		return true
	end
	vim.fn.setqflist({}, " ", { title = "HyperMax search: " .. query, items = items })
	if not Ensure_Editor_Window() then Notify("Could not open the quickfix list", vim.log.levels.ERROR); return false end
	vim.cmd("copen")
	return true
end

local function Open_Buffers()
	local choices = {}
	for _, buffer in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
		if buffer.name ~= "" then
			choices[#choices + 1] = { bufnr = buffer.bufnr, name = buffer.name, text = vim.fn.fnamemodify(buffer.name, ":~:.") }
		end
	end
	if #choices == 0 then Notify("No named buffers are open", vim.log.levels.WARN); return end
	vim.ui.select(choices, { prompt = "Switch buffer", format_item = function(item) return item.text end }, function(choice)
		if choice and Ensure_Editor_Window() then vim.api.nvim_set_current_buf(choice.bufnr) end
	end)
end

local function Project_Diagnostics(root)
	return Diagnostics.Collect(root)
end

function Workspace.Diagnostics(root)
	root = Find_Project_Root(root) or Normalize(root)
	local diagnostics = Project_Diagnostics(root)
	if #diagnostics.items == 0 then
		return Diagnostics.Open(root)
	end
	if not Ensure_Editor_Window() then
		Notify("Could not open the diagnostics list", vim.log.levels.ERROR)
		return false
	end
	return Diagnostics.Open(root)
end

local function Open_Recent_Project(index)
	local entry = State.recent_projects[index]
	if not entry or not entry.path then
		Notify("No project is assigned to shortcut " .. tostring(index), vim.log.levels.WARN)
		return false
	end
	Close()
	vim.cmd("tcd " .. vim.fn.fnameescape(entry.path))
	return require("hypermax.dashboard").Open(entry.path)
end

local function Load_Recent_Projects()
	local config_ok, Config = pcall(require, "hypermax.config")
	local directory = config_ok and Config.options and Config.options.project_dir or "~/Projects"
	local ok, projects = pcall(Project_Config.List_Projects, directory)
	State.recent_projects = {}
	State.recent_project_lines = {}
	if ok and type(projects) == "table" then
		for index = 1, math.min(3, #projects) do
			State.recent_projects[index] = projects[index]
		end
	end
end

local function Actions(root)
	local Dashboard = require("hypermax.dashboard")
	local Project = require("hypermax.project")
	local Settings = require("hypermax.settings")
	return {
		{ label = "Open project explorer", detail = "Browse files and Git state", action = function() if root then Dashboard.Open(root) else Notify("Choose a HyperMax project first", vim.log.levels.WARN) end end },
		{ label = "Switch project", detail = "Browse all registered projects", action = function() Project.List() end },
		{ label = "Open recent project", detail = "Return to the last opened project", action = function() Project.Open_Last() end },
		{ label = "Create project", detail = "Start the project setup wizard", action = function() Project.Create(require("hypermax.config").options) end },
		{ label = "Task board", detail = "Plan work and track TODO / doing / done", action = function() Flow.Open_Tasks(root) end },
		{ label = "Run configurations", detail = "Build, test and launch named commands", action = function() Flow.Open_Runners(root) end },
		{ label = "Find files", detail = "Search project files by path", action = function() Workspace.Find_Files(root) end },
		{ label = "Search in project", detail = "Search source text with ripgrep", action = function() Workspace.Search_Text(root) end },
		{ label = "Find TODO / FIXME markers", detail = "Collect project markers into the quickfix list", action = function() Workspace.Scan_Todos(root) end },
		{ label = "Project diagnostics", detail = "Review compiler and language-server diagnostics", action = function() Workspace.Diagnostics(root) end },
		{ label = "Save history / rollback", detail = "Browse hard and automatic save points", action = function() require("hypermax.history").Open(root) end },
		{ label = "Create hard save point", detail = "Save the current project workspace", action = function() local ok, result = require("hypermax.history").Save(root, "hard"); Notify(ok and ("Hard save created: " .. result.id) or tostring(result), ok and vim.log.levels.INFO or vim.log.levels.ERROR) end },
		{ label = "Git status", detail = "Open a terminal in the current repository", action = function() Workspace.Git_Status(root) end },
		{ label = "Save current project as layout", detail = "Capture structure and editable file contents", action = function() Project.Save_Layout() end },
		{ label = "Apply a layout to a new project", detail = "Choose a reusable project template", action = function() Project.Load_Layout() end },
		{ label = "Settings", detail = "Configure HyperMax defaults", action = function() Settings.Open() end },
		{ label = "Tutorials", detail = "Open the independent Essentials and Advanced guides", action = function() require("hypermax.tutorial").Open_Menu(root) end },
		{ label = "Switch buffer", detail = "Move between open files", action = Open_Buffers },
		{ label = "Health checks", detail = "Check HyperMax installation, settings and dependencies", action = function() vim.cmd("checkhealth hypermax") end },
	}
end

function Workspace.Palette(root)
	root = Find_Project_Root(root) or Normalize(root)
	local actions = Actions(root)
	vim.ui.select(actions, {
		prompt = "HyperMax Command Palette",
		format_item = function(item) return item.label .. "  —  " .. item.detail end,
	}, function(choice)
		if choice and choice.action then
			Close()
			choice.action()
		end
	end)
end

local function Render()
	local root = State.root
	Load_Recent_Projects()
	local lines = {
		"  ◆  HYPERMAX",
		"  One workspace for projects, code, builds and delivery.",
		"",
	}
	if root then
		local git = Git.Snapshot(root)
		local summary = Flow.Get_Summary(root) or { todo = 0, doing = 0, done = 0, runners = 0, total = 0 }
		local diagnostics = Project_Diagnostics(root)
		local name = vim.fs.basename(root)
		lines[#lines + 1] = "  PROJECT  /  " .. name
		lines[#lines + 1] = "  " .. root
		lines[#lines + 1] = string.format("  %s  ·  %d changed files  ·  %d tasks open  ·  %d run configs",
			git.available and ("Git " .. (git.branch or "")) or "Git not initialized",
			vim.tbl_count(git.statuses or {}), summary.todo + summary.doing, summary.runners)
		local percent = summary.total > 0 and math.floor((summary.done / summary.total) * 100) or 0
		local filled = math.floor((percent / 100) * 12)
		local progress = string.rep("█", filled) .. string.rep("░", 12 - filled)
		lines[#lines + 1] = string.format("  Diagnostics: %d errors · %d warnings · %d other   Tasks: %d/%d [%s] %d%%",
			diagnostics.errors, diagnostics.warnings, diagnostics.info + diagnostics.hints,
			summary.done, summary.total, progress, percent)
	else
		lines[#lines + 1] = "  No HyperMax project is active. Create, convert or switch to a project to unlock project tools."
	end
	if #State.recent_projects > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "  RECENT PROJECTS  /  SELECT A ROW AND PRESS ENTER"
		for index, project in ipairs(State.recent_projects) do
			local language = project.language and project.language ~= "unknown" and (" · " .. project.language) or ""
			lines[#lines + 1] = string.format("   %d   %s%s   —   %s", index, project.name or vim.fs.basename(project.path), language, vim.fn.fnamemodify(project.path, ":~"))
			State.recent_project_lines[#lines] = index
		end
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "  WORKSPACE"
	lines[#lines + 1] = "  ─────────────────────────────────────────────────────────────────────────────"
	lines[#lines + 1] = "   p   Switch project                 n   New project"
	lines[#lines + 1] = "   e   Project explorer               o   Open recent project"
	lines[#lines + 1] = "   t   Task board                     w   Run configurations"
	lines[#lines + 1] = "   f   Find files                     /   Search project text"
	lines[#lines + 1] = "   d   Find TODO / FIXME markers      x   Project diagnostics"
	lines[#lines + 1] = "   H   Save history / rollback        S   Create hard save"
	lines[#lines + 1] = "   g   Git status                     b   Switch buffer"
	lines[#lines + 1] = ""
	lines[#lines + 1] = "  CUSTOMIZE"
	lines[#lines + 1] = "  ─────────────────────────────────────────────────────────────────────────────"
	lines[#lines + 1] = "   l   Save layout                    L   Apply layout"
	lines[#lines + 1] = "   s   Settings                       h   Health checks"
	lines[#lines + 1] = "   T   Tutorials                      "
	lines[#lines + 1] = ""
	lines[#lines + 1] = "  SPACE  Command palette              q   Close workspace"
	Set_Lines(lines)
	if State.window and vim.api.nvim_win_is_valid(State.window) then
		local first_recent_line
		for line in pairs(State.recent_project_lines) do
			if not first_recent_line or line < first_recent_line then first_recent_line = line end
		end
		if first_recent_line then vim.api.nvim_win_set_cursor(State.window, { first_recent_line, 0 }) end
	end
end

function Workspace.Open(root)
	State.root = Find_Project_Root(root) or Find_Project_Root(vim.fn.getcwd()) or nil
	if State.root then
		local marked, mark_error = Project_Config.Mark_Project_Opened(State.root)
		if not marked then Notify("Workspace opened, but recent-project history could not be updated: " .. tostring(mark_error), vim.log.levels.WARN) end
	end
	Open_Window()
	Map("q", Close, "Close HyperMax workspace")
	Map(" ", function() Workspace.Palette(State.root or vim.fn.getcwd()) end, "Open command palette")
	Map("p", function() Close(); require("hypermax.project").List() end, "Switch project")
	Map("n", function() Close(); require("hypermax.project").Create(require("hypermax.config").options) end, "Create project")
	Map("o", function() Close(); require("hypermax.project").Open_Last() end, "Open recent project")
	Map("e", function() local root = State.root; Close(); if root then require("hypermax.dashboard").Open(root) else Notify("Choose a project first", vim.log.levels.WARN) end end, "Open project explorer")
	Map("t", function() local root = State.root; Close(); Flow.Open_Tasks(root) end, "Open task board")
	Map("w", function() local root = State.root; Close(); Flow.Open_Runners(root) end, "Open run configurations")
	Map("f", function() Workspace.Find_Files(State.root or vim.fn.getcwd()) end, "Find project file")
	Map("/", function() Workspace.Search_Text(State.root or vim.fn.getcwd()) end, "Search project text")
	Map("d", function() Workspace.Scan_Todos(State.root or vim.fn.getcwd()) end, "Find TODO and FIXME markers")
	Map("x", function() Workspace.Diagnostics(State.root or vim.fn.getcwd()) end, "Show project diagnostics")
	Map("H", function() Close(); require("hypermax.history").Open(State.root) end, "Open save history and rollbacks")
	Map("S", function()
		local root = State.root
		local ok, result = require("hypermax.history").Save(root, "hard")
		Notify(ok and ("Hard save created: " .. result.id) or tostring(result), ok and vim.log.levels.INFO or vim.log.levels.ERROR)
	end, "Create a hard save point")
	Map("g", function() Workspace.Git_Status(State.root or vim.fn.getcwd()) end, "Show Git status")
	Map("b", Open_Buffers, "Switch buffer")
	Map("<CR>", function()
		if not State.window or not vim.api.nvim_win_is_valid(State.window) then return end
		local line = vim.api.nvim_win_get_cursor(State.window)[1]
		local index = State.recent_project_lines[line]
		if index then Open_Recent_Project(index)
		else Notify("Move the cursor to a recent-project row, or press p to open the project picker", vim.log.levels.INFO) end
	end, "Open the selected recent project")
	Map("l", function() Close(); require("hypermax.project").Save_Layout() end, "Save current directory as a layout")
	Map("L", function() Close(); require("hypermax.project").Load_Layout() end, "Apply a project layout")
	Map("s", function() Close(); require("hypermax.settings").Open() end, "Open settings")
	Map("T", function() require("hypermax.tutorial").Open_Menu(State.root) end, "Open Essentials and Advanced tutorials")
	Map("h", function() Close(); require("hypermax.keymaps").Run_Health_Check() end, "Run health checks")
	Render()
	return true
end

function Workspace.Close()
	Close()
end

function Workspace.Get_State()
	return State
end

return Workspace
