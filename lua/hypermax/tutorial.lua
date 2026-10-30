-- Persistent, independently tracked Essentials and Advanced tutorials.
-- First-run state is stored in stdpath('data'), not in the plugin version or
-- project metadata, so updates never trigger the introduction again.
local Tutorial = { storage_path = nil }

local Window = require("hypermax.window")

local LESSONS = {
	essentials = {
		{
			id = "welcome",
			title = "Welcome to HyperMax",
			description = "The basics and how HyperMax fits into Neovim.",
			content = {
				"HyperMax adds project tools to Neovim. It does not replace Neovim's",
				"normal editing workflow: files are still ordinary buffers, and you",
				"still use your usual motions, commands, and plugins.",
				"",
				"GETTING STARTED",
				"• Create a project with :HyperMax project create, or open an existing",
				"  HyperMax project with :HyperMax workspace.",
				"• The project explorer lets you browse files and open them with Enter.",
				"• Edit code normally and save it with :write (or :w).",
				"• Open the task board with :HyperMax workspace tasks.",
				"• Open run configurations with :HyperMax workspace runs.",
				"• Open settings with :HyperMax settings.",
				"",
				"MENU AND HELP",
				"Use :HyperMax workspace for the main HyperMax home. Choose Tutorials there",
				"to return to Essentials or explore the separate Advanced track.",
			},
		},
		{
			id = "projects",
			title = "Projects and the dashboard",
			description = "Create, open, and navigate a HyperMax project.",
			content = {
				"A HyperMax project is a normal directory with a .hmc metadata folder.",
				"That folder stores project settings, layout information, and tasks.",
				"",
				"CREATE OR OPEN",
				"• :HyperMax project create starts the project creation wizard.",
				"• :HyperMax workspace opens the workspace home.",
				"• :HyperMax project convert [directory] adds HyperMax metadata to an existing",
				"  folder without changing its source files.",
				"• Use the Projects or recent-project actions to switch projects.",
				"",
				"DASHBOARD",
				"The project dashboard is a file explorer. Press Enter on a folder",
				"to expand it, or Enter on a file to open it in an editor window.",
				"Press q to close the dashboard panel.",
			},
		},
		{
			id = "editing",
			title = "Editing and saving files",
			description = "Use ordinary Neovim buffers inside your project.",
			content = {
				"HyperMax does not use a special file format for source code. Files",
				"opened from the dashboard are ordinary Neovim buffers.",
				"",
				"• Use your normal Neovim editing keys and commands.",
				"• :write or :w saves the current file.",
				"• Use the dashboard to create, rename, move, or delete project files.",
				"• :edit path/to/file opens a file by path.",
				"• :HyperMax workspace palette opens project actions such as file finding and",
				"  searching source text (ripgrep is required for text search).",
				"",
				"Project files remain on disk as normal files, so Git and other tools",
				"can work with them without importing or exporting anything.",
			},
		},
		{
			id = "tasks",
			title = "Tasks and TODOs",
			description = "Track work and keep important tasks visible while editing.",
			content = {
				"Open the task board with :HyperMax workspace tasks or :HyperMax workspace tasks.",
				"",
				"TASK BOARD KEYS",
				"• a adds a task; e edits the selected task.",
				"• s cycles its status; p cycles its priority.",
				"• P pins or unpins it; d toggles completion; x deletes it.",
				"• Enter shows the task details; q closes the board.",
				"",
				"Pinned tasks appear in the editor's winbar while you work in a",
				"buffer belonging to that project. They stay visible as you scroll.",
				"Task data is saved in the project's .hmc/workspace.json file.",
			},
		},
		{
			id = "running",
			title = "Build and run your project",
			description = "Create a named command and run it in a terminal split.",
			content = {
				"Open run configurations with :HyperMax workspace runs or :HyperMax workspace runs.",
				"",
				"• Press a to create a named build, test, or run command.",
				"• Give it a project-relative working directory ('.' means project root).",
				"• Select it and press Enter or r to execute it in a terminal split.",
				"• Use e to edit a configuration and x to delete one.",
				"",
				"Commands are user-authored shell commands. Review them before running",
				"commands in projects you do not trust. HyperMax restricts the working",
				"directory to an existing path inside the project.",
			},
		},
		{
			id = "settings",
			title = "Settings and help",
			description = "Find commands and adjust HyperMax defaults.",
			content = {
				"Open settings with :HyperMax settings or choose Settings from the",
				"main menu (:HyperMax workspace). Settings are grouped into categories.",
				"",
				"• Global settings control defaults for newly created projects.",
				"• Project settings are stored in that project's .hmc/config.json.",
				"• Use :HyperMax tutorial to reopen the tutorial menu at any time.",
				"• Use :help hypermax for the reference documentation.",
				"",
				"The Essentials and Advanced tracks have separate completion states.",
				"Completing or resetting one track does not change the other.",
			},
		},
	},
	advanced = {
		{
			id = "layouts",
			title = "Reusable project layouts",
			description = "Capture and apply directory structures and starter files.",
			content = {
				"Layouts are reusable project templates. A layout can describe nested",
				"directories and include starter-file contents.",
				"",
				"• :HyperMax layout save captures the current directory as a layout draft.",
				"• :HyperMax layout edit opens an existing layout for editing.",
				"• Use the workspace menu's layout actions to save or apply layouts.",
				"• Layout data is stored separately from each project's live source.",
				"",
				"Project captures omit protected metadata and known credential files.",
				"Review a layout before using it to create a new project.",
			},
		},
		{
			id = "git",
			title = "Git integration",
			description = "Inspect changes and perform common Git actions in the dashboard.",
			content = {
				"The dashboard displays Git markers beside files when the project is",
				"inside a Git repository.",
				"",
				"• Press g in the dashboard to open Git actions.",
				"• Stage or unstage a selected file, or stage all changes.",
				"• Commit staged changes with a message.",
				"• Fetch, pull, push, inspect branches/remotes/tags, and view diffs.",
				"• Press G to initialize Git when the directory is not yet a repository.",
				"",
				"HyperMax passes Git arguments without shell interpolation. Review the",
				"changes shown by Git before committing or pushing them.",
			},
		},
		{
			id = "history",
			title = "Save points and rollback",
			description = "Create hard saves, inspect automatic saves, and restore safely.",
			content = {
				"Use :HyperMax history save or :HyperMax history save to create a manual hard save.",
				"Use :HyperMax history or :HyperMax history to browse save points.",
				"",
				"• Soft save points are created after successful configured runs unless",
				"  the project's auto-save-after-success setting is disabled.",
				"• Select a save point to inspect, delete, or restore it.",
				"• Rollback creates a safety save of the current project first.",
				"• Git metadata is preserved and history is not recursively snapshotted.",
				"",
				"A rollback can be refused when the target or safety snapshot is",
				"incomplete. Do not treat a save point as a replacement for Git or",
				"another independent backup.",
			},
		},
		{
			id = "diagnostics",
			title = "Diagnostics and quickfix",
			description = "Collect project diagnostics and navigate the resulting list.",
			content = {
				"HyperMax can collect Neovim diagnostics from buffers belonging to",
				"the current project and show them in the quickfix list.",
				"",
				"• Run :HyperMax workspace diagnostics or choose Project diagnostics in the",
				"  workspace command palette.",
				"• The list includes diagnostic severity and source information where",
				"  the diagnostic provider supplied it.",
				"• Open quickfix entries to jump to the reported file and position.",
				"• An empty result clears stale entries from the previous project.",
				"",
				"Diagnostics are collected from active Neovim diagnostic sources;",
				"HyperMax does not install language servers or compilers for you.",
			},
		},
		{
			id = "workspace",
			title = "Workspace settings and exclusions",
			description = "Configure project-specific interface and file visibility.",
			content = {
				"Project-specific settings are stored in .hmc/config.json. They travel",
				"with the project and are separate from global HyperMax defaults.",
				"",
				"Workspace settings include:",
				"• Entry-point file and function.",
				"• Hidden-file visibility and relative exclude patterns.",
				"• Tabline visibility and floating-window placement.",
				"• Pinned-task placement in the task board.",
				"• Automatic soft saves after successful configured runs.",
				"",
				"The .git and .hmc metadata directories remain protected. Exclusion",
				"patterns are project-relative; simple names and wildcards apply at",
				"any depth in the dashboard tree.",
			},
		},
		{
			id = "task-pinning",
			title = "Pinned tasks in the editor",
			description = "Keep selected work visible in every editor window for the project.",
			content = {
				"Pin a task in the task board by selecting it and pressing P.",
				"HyperMax then adds a pinned-task summary to the editor winbar for",
				"buffers inside that project. The winbar remains visible while the",
				"buffer scrolls, and each split can show its project's own tasks.",
				"",
				"Unpin the task with P to remove it from the editor display. The task",
				"itself stays in the task board; pinning only controls its visibility.",
				"Task title and status are stored in .hmc/workspace.json.",
				"",
				"If you already use a custom winbar expression, HyperMax leaves it",
				"untouched rather than replacing your custom expression.",
			},
		},
		{
			id = "search-and-markers",
			title = "Search and source markers",
			description = "Find files, search text, and collect TODO/FIXME markers.",
			content = {
				"The workspace palette provides file finding, text search, and marker",
				"scanning for the current project.",
				"",
				"• Find files with the project file picker; ripgrep is optional because",
				"  HyperMax has a bounded filesystem fallback.",
				"• Search project text with ripgrep (rg).",
				"• Scan TODO, FIXME, BUG, and HACK markers into quickfix.",
				"• Quickfix entries open the matching file and line.",
				"",
				"The scanner skips .git and .hmc metadata so project internals are not",
				"reported as source markers.",
			},
		},
	},
}

local state = {
	buffer = nil,
	window = nil,
	view = "menu",
	category = "essentials",
	lesson_index = 1,
	items = {},
	lines = {},
}

local cached_data
local cached_path

local function Data_Path()
	return Tutorial.storage_path or (vim.fn.stdpath("data") .. "/hypermax/tutorial_progress.json")
end

local function Default_Data()
	return {
		schema = 1,
		first_run_completed = false,
		essentials = {},
		advanced = {},
	}
end

local function Normalize_Data(data)
	data = type(data) == "table" and data or {}
	local normalized = Default_Data()
	normalized.first_run_completed = data.first_run_completed == true
	for _, category in ipairs({ "essentials", "advanced" }) do
		if type(data[category]) == "table" then
			for id, completed in pairs(data[category]) do
				if type(id) == "string" and completed == true then
					normalized[category][id] = true
				end
			end
		end
	end
	return normalized
end

local function Load_Data()
	local path = Data_Path()
	if cached_data and cached_path == path then return cached_data end
	local data = Default_Data()
	local file = io.open(path, "rb")
	if file then
		local content = file:read("*a")
		file:close()
		if content and content ~= "" then
			local ok, decoded = pcall(vim.json.decode, content)
			if ok and type(decoded) == "table" then
				data = Normalize_Data(decoded)
			else
				vim.notify("HyperMax: Tutorial progress JSON is invalid; starting with empty progress.", vim.log.levels.WARN)
			end
		end
	end
	cached_data, cached_path = data, path
	return cached_data
end

local function Save_Data()
	local path = Data_Path()
	local directory = vim.fn.fnamemodify(path, ":h")
	vim.fn.mkdir(directory, "p")
	local ok, encoded = pcall(vim.json.encode, Load_Data())
	if not ok then return false, "Could not encode tutorial progress: " .. tostring(encoded) end
	local temporary = path .. ".tmp"
	local file, err = io.open(temporary, "wb")
	if not file then return false, "Could not write tutorial progress: " .. tostring(err) end
	local wrote, write_error = file:write(encoded, "\n")
	local closed, close_error = file:close()
	if not wrote or closed == nil then
		pcall(os.remove, temporary)
		return false, "Could not finish tutorial progress write: " .. tostring(write_error or close_error)
	end
	local renamed, rename_error = (vim.uv or vim.loop).fs_rename(temporary, path)
	if not renamed then
		pcall(os.remove, temporary)
		return false, "Could not replace tutorial progress: " .. tostring(rename_error)
	end
	cached_path = path
	return true
end

local function Find_Lesson(category, id)
	for index, lesson in ipairs(LESSONS[category] or {}) do
		if lesson.id == id then return lesson, index end
	end
	return nil
end

function Tutorial.Get_Lessons(category)
	if category ~= "essentials" and category ~= "advanced" then return {} end
	return vim.deepcopy(LESSONS[category])
end

function Tutorial.Get_Progress(category)
	if category ~= "essentials" and category ~= "advanced" then return 0, 0 end
	local data = Load_Data()
	local completed = 0
	for _, lesson in ipairs(LESSONS[category]) do
		if data[category][lesson.id] == true then completed = completed + 1 end
	end
	return completed, #LESSONS[category]
end

function Tutorial.Is_Completed(category, id)
	if not Find_Lesson(category, id) then return false end
	return Load_Data()[category][id] == true
end

function Tutorial.Set_Completed(category, id, completed)
	if not Find_Lesson(category, id) then return false, "Unknown tutorial lesson" end
	local data = Load_Data()
	data[category][id] = completed == true and true or nil
	return Save_Data()
end

function Tutorial.Reset_Progress(category)
	if category ~= "essentials" and category ~= "advanced" then return false, "Unknown tutorial category" end
	local data = Load_Data()
	data[category] = {}
	return Save_Data()
end

function Tutorial.First_Run_Completed()
	return Load_Data().first_run_completed == true
end

function Tutorial.Mark_First_Run_Completed()
	local data = Load_Data()
	data.first_run_completed = true
	return Save_Data()
end

function Tutorial.Reset_Cache()
	cached_data, cached_path = nil, nil
end

local function Close_Window()
	if state.window and vim.api.nvim_win_is_valid(state.window) then
		pcall(vim.api.nvim_win_close, state.window, true)
	end
	state.window, state.buffer = nil, nil
end

local function Set_Lines(lines)
	if not state.buffer or not vim.api.nvim_buf_is_valid(state.buffer) then return end
	vim.api.nvim_set_hl(0, "HyperMaxTutorialTitle", { link = "Title", default = true })
	vim.api.nvim_set_hl(0, "HyperMaxTutorialSection", { link = "Special", default = true })
	vim.api.nvim_set_hl(0, "HyperMaxTutorialMuted", { link = "Comment", default = true })
	vim.bo[state.buffer].modifiable = true
	vim.api.nvim_buf_set_lines(state.buffer, 0, -1, false, lines)
	vim.bo[state.buffer].modifiable = false
	vim.bo[state.buffer].modified = false
	local namespace = vim.api.nvim_create_namespace("HyperMaxTutorialHighlights")
	vim.api.nvim_buf_clear_namespace(state.buffer, namespace, 0, -1)
	for index, line in ipairs(lines) do
		local group
		if index == 1 then group = "HyperMaxTutorialTitle"
		elseif line:match("^[A-Z][A-Z /&%-]+$") then group = "HyperMaxTutorialSection"
		elseif line:match("^  %([A-Z]%)") or line:match("^  Press ") then group = "HyperMaxTutorialMuted" end
		if group then vim.api.nvim_buf_add_highlight(state.buffer, namespace, group, index - 1, 0, -1) end
	end
end

local function Map(key, callback, description)
	vim.keymap.set("n", key, callback, {
		buffer = state.buffer,
		silent = true,
		nowait = true,
		desc = "HyperMax tutorial: " .. description,
	})
end

local function Open_Window(title, lines, root)
	Close_Window()
	local width = math.max(32, math.min(92, vim.o.columns - 4))
	local height = math.max(10, math.min(28, vim.o.lines - 5))
	local buffer = vim.api.nvim_create_buf(false, true)
	vim.bo[buffer].buftype = "nofile"
	vim.bo[buffer].bufhidden = "wipe"
	vim.bo[buffer].swapfile = false
	vim.bo[buffer].filetype = "hypermaxtutorial"
	local window = Window.Open_Float(buffer, title, width, height, root)
	vim.wo[window].wrap = true
	vim.wo[window].linebreak = true
	vim.wo[window].number = false
	vim.wo[window].relativenumber = false
	vim.wo[window].signcolumn = "no"
	vim.wo[window].cursorline = true
	vim.wo[window].winhl = "Normal:NormalFloat,FloatBorder:FloatBorder,CursorLine:CursorLine"
	state.buffer, state.window = buffer, window
	Set_Lines(lines)
	return true
end

local function Render_Menu(root)
	state.view = "menu"
	local essential_done, essential_total = Tutorial.Get_Progress("essentials")
	local advanced_done, advanced_total = Tutorial.Get_Progress("advanced")
	local lines = {
		"HYPERMAX  /  TUTORIALS",
		"Choose a learning track. Each track keeps its own completion progress.",
		"",
		string.format("  [E]  ESSENTIALS   %d / %d lessons complete", essential_done, essential_total),
		string.format("  [A]  ADVANCED     %d / %d lessons complete", advanced_done, advanced_total),
		"",
		"Essentials introduces the everyday project workflow.",
		"Advanced explains the additional tools and project controls.",
		"",
		"  e / a  Open a track    r  Reset selected track    q  Close",
	}
	Open_Window("HyperMax  ·  Tutorials", lines, root)
	state.items = { [4] = "essentials", [5] = "advanced" }
	Map("e", function() Tutorial.Open_Category("essentials", root) end, "Open Essentials")
	Map("a", function() Tutorial.Open_Category("advanced", root) end, "Open Advanced")
	Map("<CR>", function()
		local category = state.items[vim.api.nvim_win_get_cursor(state.window)[1]]
		if category then Tutorial.Open_Category(category, root) end
	end, "Open selected track")
	Map("r", function()
		local category = state.items[vim.api.nvim_win_get_cursor(state.window)[1]]
		if not category then category = "essentials" end
		vim.ui.select({ "Reset progress", "Cancel" }, { prompt = "Reset " .. category:sub(1, 1):upper() .. category:sub(2) .. " tutorial progress?" }, function(choice)
			if choice ~= "Reset progress" then return end
			local ok, err = Tutorial.Reset_Progress(category)
			if not ok then vim.notify("HyperMax: " .. tostring(err), vim.log.levels.ERROR) end
			Render_Menu(root)
		end)
	end, "Reset selected track progress")
	Map("q", Close_Window, "Close tutorials")
	vim.api.nvim_win_set_cursor(state.window, { 4, 0 })
end

function Tutorial.Open_Category(category, root)
	if category ~= "essentials" and category ~= "advanced" then return false end
	state.category = category
	state.view = "category"
	local lessons = LESSONS[category]
	local completed = Load_Data()[category]
	local title = category == "essentials" and "ESSENTIALS" or "ADVANCED"
	local lines = { "HYPERMAX  /  " .. title, "Select a lesson. Completed lessons are saved independently.", "" }
	state.items = {}
	for index, lesson in ipairs(lessons) do
		local marker = completed[lesson.id] and "[x]" or "[ ]"
		lines[#lines + 1] = string.format("  %s  %s  —  %s", marker, lesson.title, lesson.description)
		state.items[#lines] = lesson.id
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "  Enter  Open lesson    r  Reset this track    b  Back    q  Close"
	Open_Window("HyperMax  ·  " .. title, lines, root)
	Map("<CR>", function()
		local id = state.items[vim.api.nvim_win_get_cursor(state.window)[1]]
		if id then Tutorial.Open_Lesson(category, id, root) end
	end, "Open selected lesson")
	Map("r", function()
		vim.ui.select({ "Reset progress", "Cancel" }, { prompt = "Reset " .. title:lower() .. " progress?" }, function(choice)
			if choice ~= "Reset progress" then return end
			local ok, err = Tutorial.Reset_Progress(category)
			if not ok then vim.notify("HyperMax: " .. tostring(err), vim.log.levels.ERROR) end
			Tutorial.Open_Category(category, root)
		end)
	end, "Reset this track")
	Map("b", function() Render_Menu(root) end, "Back to tutorial tracks")
	Map("q", Close_Window, "Close tutorials")
	if #lessons > 0 then vim.api.nvim_win_set_cursor(state.window, { 4, 0 }) end
	return true
end

function Tutorial.Open_Lesson(category, id, root)
	local lesson, index = Find_Lesson(category, id)
	if not lesson then return false end
	state.category, state.lesson_index, state.view = category, index, "lesson"
	local completed, total = Tutorial.Get_Progress(category)
	local lines = { "HYPERMAX  /  " .. (category == "essentials" and "ESSENTIALS" or "ADVANCED"), lesson.title, "" }
	vim.list_extend(lines, lesson.content)
	lines[#lines + 1] = ""
	lines[#lines + 1] = string.format("Track progress: %d / %d complete", completed, total)
	lines[#lines + 1] = Tutorial.Is_Completed(category, id) and "  [x] Lesson completed" or "  [ ] Lesson not completed"
	lines[#lines + 1] = ""
	lines[#lines + 1] = "  c  Toggle complete    n / p  Next / previous    b  Lesson list    q  Close"
	Open_Window("HyperMax  ·  " .. lesson.title, lines, root)
	Map("c", function()
		local ok, err = Tutorial.Set_Completed(category, id, not Tutorial.Is_Completed(category, id))
		if not ok then vim.notify("HyperMax: " .. tostring(err), vim.log.levels.ERROR) end
		Tutorial.Open_Lesson(category, id, root)
	end, "Toggle lesson completion")
	Map("n", function()
		local next_lesson = LESSONS[category][math.min(index + 1, #LESSONS[category])]
		if next_lesson then Tutorial.Open_Lesson(category, next_lesson.id, root) end
	end, "Next lesson")
	Map("p", function()
		local previous = LESSONS[category][math.max(index - 1, 1)]
		if previous then Tutorial.Open_Lesson(category, previous.id, root) end
	end, "Previous lesson")
	Map("b", function() Tutorial.Open_Category(category, root) end, "Back to lesson list")
	Map("q", Close_Window, "Close tutorial lesson")
	vim.api.nvim_win_set_cursor(state.window, { 1, 0 })
	return true
end

function Tutorial.Open_Menu(root)
	Render_Menu(root)
	return true
end

function Tutorial.Startup_Check()
	if Tutorial.First_Run_Completed() then return false end
	local opened = Tutorial.Open_Lesson("essentials", "welcome")
	if opened then
		local saved, err = Tutorial.Mark_First_Run_Completed()
		if not saved then vim.notify("HyperMax: Could not persist first-run tutorial state: " .. tostring(err), vim.log.levels.WARN) end
	end
	return opened
end

function Tutorial.Setup_Startup()
	if Tutorial._startup_registered then return end
	Tutorial._startup_registered = true
	local function Run()
		vim.schedule(function()
			local ok, err = pcall(Tutorial.Startup_Check)
			if not ok then vim.notify("HyperMax: Could not open the welcome tutorial: " .. tostring(err), vim.log.levels.WARN) end
		end)
	end
	if vim.v.vim_did_enter == 1 then
		Run()
	else
		local group = vim.api.nvim_create_augroup("HyperMaxTutorialStartup", { clear = true })
		vim.api.nvim_create_autocmd("VimEnter", { group = group, once = true, callback = Run })
	end
end

function Tutorial.Close()
	Close_Window()
end

function Tutorial.Get_State()
	return state
end

return Tutorial
