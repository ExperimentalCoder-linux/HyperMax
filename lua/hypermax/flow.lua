-- HyperMax project task board and run configurations.
-- All project-specific state is stored under .hmc/workspace.json.
local Flow = {}
local Project_Config = require("hypermax.project_config")
local Window = require("hypermax.window")

local SCHEMA_VERSION = 1
local STATUS = { "todo", "doing", "done" }
local PRIORITY = { "low", "normal", "high" }
local active = { root = nil, buffer = nil, window = nil, mode = nil, items = {}, lines = {} }

local function Join(...)
	return table.concat({ ... }, "/"):gsub("/+", "/")
end

local function Normalize_Root(root)
	if not root or root == "" then
		local current_buffer = vim.api.nvim_buf_get_name(0)
		root = current_buffer ~= "" and current_buffer or vim.fn.getcwd()
	end
	return vim.fn.fnamemodify(vim.fn.expand(root), ":p"):gsub("/+$", "")
end

local function Is_Project(root)
	local metadata_directory = Join(root, ".hmc")
	if vim.fn.isdirectory(metadata_directory) ~= 1 then return false end
	-- .hmc is the trust boundary for project-local state. Do not follow a
	-- symlink here: otherwise workspace.json could be written outside the root.
	local stat = (vim.uv or vim.loop).fs_lstat(metadata_directory)
	return stat ~= nil and stat.type == "directory"
end

local function Find_Root(path)
	path = Normalize_Root(path)
	if vim.fn.filereadable(path) == 1 then path = vim.fn.fnamemodify(path, ":h") end
	while path and path ~= "" do
		if Is_Project(path) then return path end
		local parent = vim.fn.fnamemodify(path, ":h")
		if parent == path then break end
		path = parent
	end
	return nil
end

local function Data_Path(root)
	return Join(root, ".hmc", "workspace.json")
end

local function Clean_String(value, fallback, limit)
	if type(value) ~= "string" then return fallback end
	value = vim.trim(value)
	if value == "" then return fallback end
	return value:sub(1, limit or 2000)
end

local function Includes(list, value)
	for _, candidate in ipairs(list) do if candidate == value then return true end end
	return false
end

local function Normalize_Data(data)
	data = type(data) == "table" and data or {}
	local normalized = { version = SCHEMA_VERSION, tasks = {}, runners = {} }
	local task_ids, runner_ids = {}, {}

	for index, item in ipairs(type(data.tasks) == "table" and data.tasks or {}) do
		if type(item) == "table" then
			local id = Clean_String(item.id, "task-" .. index, 100)
			if not task_ids[id] then
				task_ids[id] = true
				local status = Includes(STATUS, item.status) and item.status or "todo"
				local priority = Includes(PRIORITY, item.priority) and item.priority or "normal"
				normalized.tasks[#normalized.tasks + 1] = {
					id = id,
					title = Clean_String(item.title, "Untitled task", 180),
					detail = Clean_String(item.detail, "", 4000),
					status = status,
					priority = priority,
					pinned = item.pinned == true,
					pinned_at = item.pinned == true and (tonumber(item.pinned_at) or tonumber(item.updated_at) or os.time()) or nil,
					created_at = tonumber(item.created_at) or os.time(),
					updated_at = tonumber(item.updated_at) or tonumber(item.created_at) or os.time(),
				}
			end
		end
	end

	for index, item in ipairs(type(data.runners) == "table" and data.runners or {}) do
		if type(item) == "table" then
			local id = Clean_String(item.id, "run-" .. index, 100)
			local command = Clean_String(item.command, nil, 4000)
			if command and not runner_ids[id] then
				runner_ids[id] = true
				local cwd = Clean_String(item.cwd, ".", 500):gsub("\\", "/")
				if cwd == "" then cwd = "." end
				normalized.runners[#normalized.runners + 1] = {
					id = id,
					name = Clean_String(item.name, "Run configuration " .. index, 120),
					command = command,
					cwd = cwd,
					description = Clean_String(item.description, "", 500),
					last_run = tonumber(item.last_run),
					last_exit_code = tonumber(item.last_exit_code),
				}
			end
		end
	end

	return normalized
end

local function Read_Data(root)
	local path = Data_Path(root)
	local stat = (vim.uv or vim.loop).fs_lstat(path)
	if stat and stat.type == "link" then
		return nil, "Refusing to read a symlinked project workspace file: " .. path
	end
	local file = io.open(path, "rb")
	if not file then return Normalize_Data({}) end
	local content = file:read("*a")
	file:close()
	if not content or content == "" then return Normalize_Data({}) end
	local ok, decoded = pcall(vim.json.decode, content)
	if not ok or type(decoded) ~= "table" then
		return nil, "Project workspace data is invalid JSON: " .. path
	end
	return Normalize_Data(decoded)
end

local function Write_Data(root, data)
	if not Is_Project(root) then return false, "Open a HyperMax project before changing its workspace data" end
	local normalized = Normalize_Data(data)
	local ok, encoded = pcall(vim.json.encode, normalized)
	if not ok then return false, "Could not encode project workspace data: " .. tostring(encoded) end
	local path = Data_Path(root)
	local temporary = path .. ".tmp"
	local temporary_stat = (vim.uv or vim.loop).fs_lstat(temporary)
	if temporary_stat and temporary_stat.type == "link" then
		return false, "Refusing to write through a symlinked workspace temporary file"
	end
	local file, err = io.open(temporary, "wb")
	if not file then return false, "Could not write workspace data: " .. tostring(err) end
	local wrote, write_error = file:write(encoded, "\n")
	local closed, close_error = file:close()
	if not wrote or closed == nil then
		pcall(os.remove, temporary)
		return false, "Could not finish writing workspace data: " .. tostring(write_error or close_error)
	end
	local renamed, rename_error = (vim.uv or vim.loop).fs_rename(temporary, path)
	if not renamed then
		pcall(os.remove, temporary)
		return false, "Could not replace workspace data: " .. tostring(rename_error)
	end
	return true
end

local function Load(root)
	root = Find_Root(root)
	if not root then return nil, "No HyperMax project found. Convert or create a project first." end
	local data, err = Read_Data(root)
	if not data then return nil, err end
	return data, nil, root
end

local function Save(root, data)
	root = Find_Root(root)
	if not root then return false, "No HyperMax project found" end
	return Write_Data(root, data)
end

local function New_ID(prefix, list)
	local base = prefix .. "-" .. tostring(os.time())
	local id, suffix = base, 1
	while true do
		local exists = false
		for _, item in ipairs(list or {}) do if item.id == id then exists = true; break end end
		if not exists then return id end
		suffix = suffix + 1
		id = base .. "-" .. suffix
	end
end

local function Find_Item(list, id)
	for index, item in ipairs(list or {}) do if item.id == id then return item, index end end
	return nil
end

function Flow.Normalize_Data(data)
	return Normalize_Data(data)
end

function Flow.Load(root)
	return Load(root)
end

function Flow.Save(root, data)
	return Save(root, data)
end

function Flow.Get_Summary(root)
	local data, err = Load(root)
	if not data then return nil, err end
	local summary = { total = #data.tasks, todo = 0, doing = 0, done = 0, runners = #data.runners }
	for _, task in ipairs(data.tasks) do summary[task.status] = (summary[task.status] or 0) + 1 end
	return summary
end

function Flow.Add_Task(root, title, detail, priority)
	local data, err, actual_root = Load(root)
	if not data then return false, err end
	title = Clean_String(title, nil, 180)
	if not title then return false, "Task title cannot be empty" end
	local task = {
		id = New_ID("task", data.tasks), title = title,
		detail = Clean_String(detail, "", 4000),
		status = "todo", priority = Includes(PRIORITY, priority) and priority or "normal",
		pinned = false,
		created_at = os.time(), updated_at = os.time(),
	}
	data.tasks[#data.tasks + 1] = task
	local ok, save_error = Save(actual_root, data)
	if not ok then return false, save_error end
	return true, task
end

function Flow.Update_Task(root, id, changes)
	local data, err, actual_root = Load(root)
	if not data then return false, err end
	local task = Find_Item(data.tasks, id)
	if not task then return false, "Task no longer exists" end
	changes = type(changes) == "table" and changes or {}
	if changes.title ~= nil then
		local title = Clean_String(changes.title, nil, 180)
		if not title then return false, "Task title cannot be empty" end
		task.title = title
	end
	if changes.detail ~= nil then task.detail = Clean_String(changes.detail, "", 4000) end
	if Includes(STATUS, changes.status) then task.status = changes.status end
	if Includes(PRIORITY, changes.priority) then task.priority = changes.priority end
	if changes.pinned ~= nil then
		task.pinned = changes.pinned == true
		task.pinned_at = task.pinned and os.time() or nil
	end
	task.updated_at = os.time()
	return Save(actual_root, data)
end

function Flow.Toggle_Task_Pinned(root, id)
	local data, err, actual_root = Load(root)
	if not data then return false, err end
	local task = Find_Item(data.tasks, id)
	if not task then return false, "Task no longer exists" end
	task.pinned = not task.pinned
	task.pinned_at = task.pinned and os.time() or nil
	task.updated_at = os.time()
	local saved, save_error = Save(actual_root, data)
	if not saved then return false, save_error end
	return true, task
end

function Flow.Delete_Task(root, id)
	local data, err, actual_root = Load(root)
	if not data then return false, err end
	local _, index = Find_Item(data.tasks, id)
	if not index then return false, "Task no longer exists" end
	table.remove(data.tasks, index)
	return Save(actual_root, data)
end

local function Is_Safe_CWD(cwd)
	if type(cwd) ~= "string" or cwd == "" or cwd:find("[%c]") or cwd:find("\\") then return false end
	if cwd:sub(1, 1) == "/" or cwd:match("^%a:") then return false end
	for part in cwd:gmatch("[^/]+") do if part == ".." then return false end end
	return true
end

local function Is_Contained_Directory(root, path)
	local uv = vim.uv or vim.loop
	local real_root = uv.fs_realpath(root)
	local real_path = uv.fs_realpath(path)
	if not real_root or not real_path then return false end
	real_root = real_root:gsub("[/\\]+$", "")
	local separator = package.config:sub(1, 1)
	if separator == "\\" then
		real_root, real_path = real_root:lower(), real_path:lower()
	end
	return real_path == real_root or real_path:sub(1, #real_root + 1) == real_root .. separator
end

function Flow.Add_Runner(root, name, command, cwd, description)
	local data, err, actual_root = Load(root)
	if not data then return false, err end
	name = Clean_String(name, nil, 120)
	command = Clean_String(command, nil, 4000)
	if not name then return false, "Run configuration name cannot be empty" end
	if not command then return false, "Command cannot be empty" end
	cwd = Clean_String(cwd, ".", 500):gsub("\\", "/")
	if not Is_Safe_CWD(cwd) then return false, "Working directory must be a safe project-relative path" end
	local full_cwd = cwd == "." and actual_root or (actual_root .. "/" .. cwd)
	if vim.fn.isdirectory(full_cwd) ~= 1 then return false, "Working directory does not exist: " .. cwd end
	if not Is_Contained_Directory(actual_root, full_cwd) then
		return false, "Working directory resolves outside the project (including through symlinks)"
	end
	local runner = { id = New_ID("run", data.runners), name = name, command = command, cwd = cwd, description = Clean_String(description, "", 500) }
	data.runners[#data.runners + 1] = runner
	local ok, save_error = Save(actual_root, data)
	if not ok then return false, save_error end
	return true, runner
end

function Flow.Update_Runner(root, id, changes)
	local data, err, actual_root = Load(root)
	if not data then return false, err end
	local runner = Find_Item(data.runners, id)
	if not runner then return false, "Run configuration no longer exists" end
	changes = type(changes) == "table" and changes or {}
	if changes.name ~= nil then
		runner.name = Clean_String(changes.name, nil, 120)
		if not runner.name then return false, "Name cannot be empty" end
	end
	if changes.command ~= nil then
		runner.command = Clean_String(changes.command, nil, 4000)
		if not runner.command then return false, "Command cannot be empty" end
	end
	if changes.cwd ~= nil then
		local cwd = Clean_String(changes.cwd, ".", 500):gsub("\\", "/")
		if not Is_Safe_CWD(cwd) then return false, "Working directory must be a safe project-relative path" end
		local full_cwd = cwd == "." and actual_root or (actual_root .. "/" .. cwd)
		if vim.fn.isdirectory(full_cwd) ~= 1 then return false, "Working directory does not exist: " .. cwd end
		if not Is_Contained_Directory(actual_root, full_cwd) then
			return false, "Working directory resolves outside the project (including through symlinks)"
		end
		runner.cwd = cwd
	end
	if changes.description ~= nil then runner.description = Clean_String(changes.description, "", 500) end
	return Save(actual_root, data)
end

function Flow.Delete_Runner(root, id)
	local data, err, actual_root = Load(root)
	if not data then return false, err end
	local _, index = Find_Item(data.runners, id)
	if not index then return false, "Run configuration no longer exists" end
	table.remove(data.runners, index)
	return Save(actual_root, data)
end

local function Notify(message, level)
	vim.notify("HyperMax: " .. message, level or vim.log.levels.INFO)
end

local function Close_Window()
	if active.window and vim.api.nvim_win_is_valid(active.window) then
		local win = active.window
		active.window = nil
		pcall(vim.api.nvim_win_close, win, true)
	end
end

local function Open_Window(title, height)
	Close_Window()
	local width = math.max(24, math.min(100, vim.o.columns - 4))
	height = math.min(height or 28, math.max(10, vim.o.lines - 6))
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "hypermaxflow"
	local win = Window.Open_Float(buf, title, width, height, active.root)
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].wrap = false
	vim.wo[win].cursorline = true
	vim.wo[win].winhl = "Normal:NormalFloat,FloatBorder:FloatBorder,CursorLine:CursorLine"
	active.buffer, active.window = buf, win
	return buf, win
end

local function Set_Lines(lines)
	if not active.buffer or not vim.api.nvim_buf_is_valid(active.buffer) then return end
	vim.api.nvim_set_hl(0, "HyperMaxFlowTitle", { link = "Title", default = true })
	vim.api.nvim_set_hl(0, "HyperMaxFlowSection", { link = "Special", default = true })
	vim.api.nvim_set_hl(0, "HyperMaxFlowMuted", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "HyperMaxFlowHigh", { link = "DiagnosticError", default = true })
	vim.api.nvim_set_hl(0, "HyperMaxFlowDone", { link = "DiagnosticOk", default = true })
	vim.bo[active.buffer].modifiable = true
	vim.api.nvim_buf_set_lines(active.buffer, 0, -1, false, lines)
	vim.bo[active.buffer].modifiable = false
	vim.bo[active.buffer].modified = false
	local namespace = vim.api.nvim_create_namespace("HyperMaxFlowHighlights")
	vim.api.nvim_buf_clear_namespace(active.buffer, namespace, 0, -1)
	for index, line in ipairs(lines) do
		local group
		if index == 1 then group = "HyperMaxFlowTitle"
		elseif line:match("^  TODO$") or line:match("^  IN PROGRESS$") or line:match("^  DONE$") then group = "HyperMaxFlowSection"
		elseif line:match("^  %-+") or line:match("^  Configurations are stored") then group = "HyperMaxFlowMuted"
		elseif line:find("[HIGH]", 1, true) or line:find("!!!", 1, true) then group = "HyperMaxFlowHigh"
		elseif line:match("^  %s*%d+%s+") then group = "HyperMaxFlowSection" end
		if group then vim.api.nvim_buf_add_highlight(active.buffer, namespace, group, index - 1, 0, -1) end
	end
end

local function Map(key, callback, description)
	vim.keymap.set("n", key, callback, { buffer = active.buffer, silent = true, nowait = true, desc = description })
end

local function Current_Item()
	if not active.window or not vim.api.nvim_win_is_valid(active.window) then return nil end
	local line = vim.api.nvim_win_get_cursor(active.window)[1]
	return active.items[line]
end

local function Focus_Editor_Window()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_is_valid(win) and win ~= active.window then
			local config = vim.api.nvim_win_get_config(win)
			if not config.relative or config.relative == "" then
				vim.api.nvim_set_current_win(win)
				Close_Window()
				return true
			end
		end
	end
	Close_Window()
	local current = vim.api.nvim_get_current_win()
	if not current or not vim.api.nvim_win_is_valid(current) then return false end
	local config = vim.api.nvim_win_get_config(current)
	return not config.relative or config.relative == ""
end

local function Render_Tasks()
	local data, err = Load(active.root)
	if not data then Notify(tostring(err), vim.log.levels.ERROR); return end
	active.items = {}
	local project_settings = Project_Config.Get_Project_Settings(active.root) or {}
	local pinned_position = project_settings.pinned_tasks_position == "bottom" and "bottom" or "top"
	local lines = {
		"  PLAN  /  TRACK  /  FINISH",
		"  Project: " .. vim.fs.basename(active.root),
		"  ─────────────────────────────────────────────────────────────────────────────",
	}
	local function Add_Pinned()
		local count = 0
		for _, task in ipairs(data.tasks) do if task.pinned then count = count + 1 end end
		if count == 0 then return end
		lines[#lines + 1] = "  PINNED TASKS  /  SAVED IN THIS WORKSPACE"
		lines[#lines + 1] = "  " .. string.rep("─", 76)
		for _, task in ipairs(data.tasks) do
			if task.pinned then
				local marker = task.priority == "high" and "!!!" or (task.priority == "low" and " · " or " ! ")
				lines[#lines + 1] = string.format("  ★ [%s] %s  [%s]", task.status:upper(), task.title, marker)
				active.items[#lines] = task
			end
		end
		lines[#lines + 1] = ""
	end
	if pinned_position == "top" then Add_Pinned() end
	lines[#lines + 1] = "  TODO"
	local function Add_Group(status, label)
		local count = 0
		for _, task in ipairs(data.tasks) do if task.status == status and not task.pinned then count = count + 1 end end
		if status ~= "todo" then lines[#lines + 1] = ""; lines[#lines + 1] = "  " .. label end
		lines[#lines + 1] = "  " .. string.rep("─", 76)
		if count == 0 then lines[#lines + 1] = "    Nothing here yet" end
		for _, task in ipairs(data.tasks) do
			if task.status == status and not task.pinned then
				local marker = task.priority == "high" and "!!!" or (task.priority == "low" and " · " or " ! ")
				lines[#lines + 1] = string.format("  %s  [%s] %s", marker, task.priority:upper(), task.title)
				active.items[#lines] = task
			end
		end
	end
	Add_Group("todo", "TODO")
	Add_Group("doing", "IN PROGRESS")
	Add_Group("done", "DONE")
	if pinned_position == "bottom" then
		lines[#lines + 1] = ""
		Add_Pinned()
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "  a Add  e Edit  s Status  p Priority  P Pin/unpin  d Done  x Delete  Enter Details  q Close"
	Set_Lines(lines)
	if active.window and vim.api.nvim_win_is_valid(active.window) then
		vim.api.nvim_win_set_cursor(active.window, { math.min(vim.api.nvim_win_get_cursor(active.window)[1], #lines), 0 })
	end
end

local function Add_Task_UI()
	vim.ui.input({ prompt = "Task title: " }, function(title)
		if not title or vim.trim(title) == "" then return end
		vim.ui.input({ prompt = "Details (optional): " }, function(detail)
			local ok, result = Flow.Add_Task(active.root, title, detail or "")
			if not ok then Notify(tostring(result), vim.log.levels.ERROR) else Render_Tasks() end
		end)
	end)
end

local function Edit_Task_UI()
	local task = Current_Item()
	if not task then Notify("Select a task first", vim.log.levels.WARN); return end
	vim.ui.input({ prompt = "Task title: ", default = task.title }, function(title)
		if not title then return end
		vim.ui.input({ prompt = "Details: ", default = task.detail }, function(detail)
			local ok, err = Flow.Update_Task(active.root, task.id, { title = title, detail = detail or "" })
			if not ok then Notify(tostring(err), vim.log.levels.ERROR) else Render_Tasks() end
		end)
	end)
end

function Flow.Open_Tasks(root)
	root = Find_Root(root)
	if not root then Notify("Open or convert a project before using its task board", vim.log.levels.WARN); return false end
	active.root, active.mode = root, "tasks"
	Open_Window("HyperMax  ·  Task Board", 30)
	Map("q", Close_Window, "Close task board")
	Map("r", Render_Tasks, "Refresh task board")
	Map("a", Add_Task_UI, "Add task")
	Map("e", Edit_Task_UI, "Edit selected task")
	Map("s", function()
		local task = Current_Item(); if not task then return end
		local index = 1; for i, value in ipairs(STATUS) do if value == task.status then index = i end end
		local next_status = STATUS[index % #STATUS + 1]
		local ok, err = Flow.Update_Task(active.root, task.id, { status = next_status })
		if not ok then Notify(tostring(err), vim.log.levels.ERROR) else Render_Tasks() end
	end, "Move task to next status")
	Map("p", function()
		local task = Current_Item(); if not task then return end
		local index = 1; for i, value in ipairs(PRIORITY) do if value == task.priority then index = i end end
		local ok, err = Flow.Update_Task(active.root, task.id, { priority = PRIORITY[index % #PRIORITY + 1] })
		if not ok then Notify(tostring(err), vim.log.levels.ERROR) else Render_Tasks() end
	end, "Cycle task priority")
	Map("P", function()
		local task = Current_Item(); if not task then return end
		local ok, result = Flow.Toggle_Task_Pinned(active.root, task.id)
		if not ok then Notify(tostring(result), vim.log.levels.ERROR)
		else Notify(result.pinned and "Task pinned in the workspace" or "Task unpinned"); Render_Tasks() end
	end, "Pin or unpin task in the workspace")
	Map("d", function()
		local task = Current_Item(); if not task then return end
		local status = task.status == "done" and "todo" or "done"
		local ok, err = Flow.Update_Task(active.root, task.id, { status = status })
		if not ok then Notify(tostring(err), vim.log.levels.ERROR) else Render_Tasks() end
	end, "Toggle task done")
	Map("x", function()
		local task = Current_Item(); if not task then return end
		vim.ui.select({ "Delete", "Cancel" }, { prompt = "Delete task: " .. task.title .. "?" }, function(choice)
			if choice ~= "Delete" then return end
			local ok, err = Flow.Delete_Task(active.root, task.id)
			if not ok then Notify(tostring(err), vim.log.levels.ERROR) else Render_Tasks() end
		end)
	end, "Delete selected task")
	Map("<CR>", function()
		local task = Current_Item(); if task then Notify(task.detail ~= "" and task.detail or "No additional details") end
	end, "Show task details")
	Render_Tasks()
	return true
end

local function Render_Runners()
	local data, err = Load(active.root)
	if not data then Notify(tostring(err), vim.log.levels.ERROR); return end
	active.items = {}
	local lines = {
		"  BUILD  /  TEST  /  RUN",
		"  Project: " .. vim.fs.basename(active.root),
		"  Configurations are stored in .hmc/workspace.json",
		"  ─────────────────────────────────────────────────────────────────────────────",
	}
	if #data.runners == 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "  No run configurations yet. Press a to create one."
	end
	for index, runner in ipairs(data.runners) do
		lines[#lines + 1] = string.format("  %2d  %s", index, runner.name)
		active.items[#lines] = runner
		lines[#lines + 1] = "      $ " .. runner.command
		lines[#lines + 1] = "      cwd: " .. runner.cwd .. (runner.last_exit_code ~= nil and ("   last exit: " .. runner.last_exit_code) or "")
		if runner.description ~= "" then lines[#lines + 1] = "      " .. runner.description end
		lines[#lines + 1] = ""
	end
	lines[#lines + 1] = "  a Add  e Edit  Enter / r Run  x Delete  q Close"
	Set_Lines(lines)
end

local function Add_Runner_UI()
	vim.ui.input({ prompt = "Configuration name: " }, function(name)
		if not name or vim.trim(name) == "" then return end
		vim.ui.input({ prompt = "Command (review before running): " }, function(command)
			if not command or vim.trim(command) == "" then return end
			vim.ui.input({ prompt = "Working directory (project-relative, . for root): ", default = "." }, function(cwd)
				local ok, result = Flow.Add_Runner(active.root, name, command, cwd or ".")
				if not ok then Notify(tostring(result), vim.log.levels.ERROR) else Render_Runners() end
			end)
		end)
	end)
end

local function Edit_Runner_UI()
	local runner = Current_Item()
	if not runner then Notify("Select a configuration first", vim.log.levels.WARN); return end
	vim.ui.input({ prompt = "Name: ", default = runner.name }, function(name)
		if not name then return end
		vim.ui.input({ prompt = "Command: ", default = runner.command }, function(command)
			if not command then return end
			vim.ui.input({ prompt = "Working directory: ", default = runner.cwd }, function(cwd)
				local ok, err = Flow.Update_Runner(active.root, runner.id, { name = name, command = command, cwd = cwd or runner.cwd })
				if not ok then Notify(tostring(err), vim.log.levels.ERROR) else Render_Runners() end
			end)
		end)
	end)
end

function Flow.Run_Runner(root, id)
	local data, err, actual_root = Load(root)
	if not data then return false, err end
	local runner = Find_Item(data.runners, id)
	if not runner then return false, "Run configuration no longer exists" end
	if not Is_Safe_CWD(runner.cwd) then return false, "Run configuration has an unsafe working directory" end
	local cwd = runner.cwd == "." and actual_root or (actual_root .. "/" .. runner.cwd)
	if vim.fn.isdirectory(cwd) ~= 1 then return false, "Working directory no longer exists: " .. runner.cwd end
	if not Is_Contained_Directory(actual_root, cwd) then
		return false, "Working directory now resolves outside the project; refusing to run"
	end

	-- Commands are user-authored project data and execute only after an explicit
	-- Run action. The command intentionally runs through the selected system shell.
	local shell, args
	if vim.fn.has("win32") == 1 then shell, args = "cmd.exe", { "/d", "/s", "/c", runner.command }
	else shell, args = "sh", { "-lc", runner.command } end
	if vim.fn.executable(shell) ~= 1 then return false, "Required shell is not available: " .. shell end
	if not Focus_Editor_Window() then return false, "Could not find an editor window for the run configuration" end
	vim.cmd("botright 14new")
	local terminal_buffer = vim.api.nvim_get_current_buf()
	vim.bo[terminal_buffer].bufhidden = "hide"
	table.insert(args, 1, shell)
	local started, job = pcall(vim.fn.termopen, args, {
		cwd = cwd,
		on_exit = function(_, exit_code)
			vim.schedule(function()
				local latest = Load(actual_root)
				if not latest then return end
				local completed = Find_Item(latest.runners, id)
				if not completed then return end
				completed.last_run = os.time()
				completed.last_exit_code = tonumber(exit_code) or -1
				Save(actual_root, latest)
				if completed.last_exit_code == 0 then
					local project_settings = Project_Config.Get_Project_Settings(actual_root) or {}
					if project_settings.auto_save_after_success ~= false then
						local History = require("hypermax.history")
						local saved, snapshot = History.Save(actual_root, "soft", "Successful run: " .. completed.name)
						if not saved then
							Notify("Run succeeded, but automatic save failed: " .. tostring(snapshot), vim.log.levels.WARN)
						end
					end
				end
				if active.mode == "runners" and active.root == actual_root then Render_Runners() end
			end)
		end,
	})
	if not started or type(job) ~= "number" or job <= 0 then
		pcall(vim.cmd, "stopinsert")
		pcall(vim.cmd, "bwipeout!")
		return false, "Could not start the run configuration terminal: " .. tostring(job)
	end
	vim.cmd("startinsert")
	runner.last_run = os.time()
	Save(actual_root, data)
	return true
end

function Flow.Close()
	Close_Window()
end

function Flow.Get_State()
	return active
end

function Flow.Refresh()
	if active.mode == "tasks" then Render_Tasks()
	elseif active.mode == "runners" then Render_Runners() end
end

function Flow.Open_Runners(root)
	root = Find_Root(root)
	if not root then Notify("Open or convert a project before creating run configurations", vim.log.levels.WARN); return false end
	active.root, active.mode = root, "runners"
	Open_Window("HyperMax  ·  Run Configurations", 26)
	Map("q", Close_Window, "Close run configurations")
	Map("r", function()
		local runner = Current_Item(); if not runner then return end
		local ok, err = Flow.Run_Runner(active.root, runner.id)
		if not ok then Notify(tostring(err), vim.log.levels.ERROR) end
	end, "Run selected configuration")
	Map("<CR>", function()
		local runner = Current_Item(); if not runner then return end
		local ok, err = Flow.Run_Runner(active.root, runner.id)
		if not ok then Notify(tostring(err), vim.log.levels.ERROR) end
	end, "Run selected configuration")
	Map("a", Add_Runner_UI, "Add run configuration")
	Map("e", Edit_Runner_UI, "Edit run configuration")
	Map("x", function()
		local runner = Current_Item(); if not runner then return end
		vim.ui.select({ "Delete", "Cancel" }, { prompt = "Delete configuration '" .. runner.name .. "'?" }, function(choice)
			if choice ~= "Delete" then return end
			local ok, err = Flow.Delete_Runner(active.root, runner.id)
			if not ok then Notify(tostring(err), vim.log.levels.ERROR) else Render_Runners() end
		end)
	end, "Delete run configuration")
	Render_Runners()
	return true
end

return Flow
