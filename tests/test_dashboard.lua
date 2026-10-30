-- =========================================================
-- HYPERMAX DASHBOARD RUNTIME TESTS
-- =========================================================
--
-- Run from the repository root:
-- nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/test_dashboard.lua"
--
-- These tests exercise real Neovim buffers and keymaps.
-- They are not substitutes for testing with your normal UI
-- plugin configuration (such as dressing.nvim).
-- =========================================================

local Passed = 0
local Failed = 0
local Failures = {}

-- Keep dashboard/project metadata tests isolated from the user's real global
-- project registry, and restore the original path after this file completes.
local Project_Config = require("hypermax.project_config")
local original_global_path = Project_Config.global_path
local test_global_root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
Project_Config.global_path = test_global_root .. "/hypermax/config.json"

local function Test(Name, Callback)
	local ok, err = xpcall(Callback, debug.traceback)

	if ok then
		Passed = Passed + 1
		print("[PASS] Dashboard: " .. Name)
	else
		Failed = Failed + 1
		Failures[#Failures + 1] = {
			name = Name,
			error = tostring(err),
		}

		print("[FAIL] Dashboard: " .. Name)
		print(tostring(err))
	end
end

local function Assert(Value, Message)
	if not Value then
		error(Message or "Assertion failed", 2)
	end
end

local function Assert_Valid_Buffer(Buffer, Message)
	Assert(type(Buffer) == "number" and vim.api.nvim_buf_is_valid(Buffer), Message or "Expected a valid Neovim buffer")
end

local function Flush_Scheduled_Callbacks()
	-- Let queued Neovim callbacks run.
	vim.wait(100, function()
		return false
	end)
end

local function Create_Test_Directory()
	local Path = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
	vim.fn.mkdir(Path .. "/.hmc", "p")

	local Basics = {
		version = 1,
		project = {
			name = "DashboardTest",
			root = Path,
			language = "c",
			manager = "native",
			creator = "tests",
			created_at = os.time(),
			entry_point = {
				file = "src/main.c",
				["function"] = "main",
			},
		},
		git = { enabled = false },
	}

	vim.fn.mkdir(Path .. "/src", "p")

	local config_file = assert(io.open(Path .. "/.hmc/basics.json", "w"))
	config_file:write(vim.json.encode(Basics))
	config_file:close()

	local main_file = assert(io.open(Path .. "/src/main.c", "w"))
	main_file:write("int main(void) { return 0; }\n")
	main_file:close()

	return Path
end

local function Remove_Test_Directory(Path)
	if Path and Path ~= "" then
		vim.fn.delete(Path, "rf")
	end
end

-- Make sure the plugin modules can be loaded.
Test("dashboard module loads", function()
	package.loaded["hypermax.dashboard"] = nil

	local Dashboard = require("hypermax.dashboard")

	Assert(type(Dashboard) == "table", "Dashboard module did not return a table")
	Assert(type(Dashboard.Open) == "function", "Dashboard.Open is missing")
	Assert(type(Dashboard.Is_Project) == "function", "Dashboard.Is_Project is missing")
end)

-- Opening a dashboard must not attempt to set keymaps on a
-- deleted or invalid buffer.
Test("opening dashboard does not use an invalid buffer", function()
	local Dashboard = require("hypermax.dashboard")
	local Root = Create_Test_Directory()

	local ok, err = pcall(Dashboard.Open, Root)

	Flush_Scheduled_Callbacks()
	Remove_Test_Directory(Root)

	Assert(ok, "Dashboard.Open raised an error: " .. tostring(err))

	Assert_Valid_Buffer(vim.api.nvim_get_current_buf(), "Current buffer became invalid after opening the dashboard")
end)

-- Opening the same project more than once must not raise
-- E95: Buffer with this name already exists.
Test("opening the same dashboard repeatedly is safe", function()
	local Dashboard = require("hypermax.dashboard")
	local Root = Create_Test_Directory()

	local ok1, err1 = pcall(Dashboard.Open, Root)
	Flush_Scheduled_Callbacks()

	Assert(ok1, "First open failed: " .. tostring(err1))

	local ok2, err2 = pcall(Dashboard.Open, Root)
	Flush_Scheduled_Callbacks()

	Remove_Test_Directory(Root)

	Assert(ok2, "Second open failed: " .. tostring(err2))
	Assert_Valid_Buffer(vim.api.nvim_get_current_buf())
end)

-- Simulate a dashboard buffer being deleted and then opened
-- again. This helps detect stale buffer IDs in keymap setup.
local Dashboard = require("hypermax.dashboard")
Test("Dashboard: dashboard can reopen after its buffer is deleted", function()
	local Root = Create_Test_Directory()
	local ok, err = pcall(Dashboard.Open, Root)
	Assert(ok, "Dashboard open failed: " .. tostring(err))

	local state = Dashboard.Get_State()
	local old_buffer = state.buffer
	local old_window = state.window

	Assert(vim.api.nvim_buf_is_valid(old_buffer), "Dashboard buffer should initially be valid")
	Assert(vim.api.nvim_win_is_valid(old_window), "Dashboard panel window should initially be valid")

	local editor_window
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if win ~= old_window then
			editor_window = win
			break
		end
	end
	Assert(editor_window ~= nil, "Dashboard should leave an editor window beside the panel")
	vim.api.nvim_set_current_win(editor_window)
	-- Neovim will keep a buffer alive while a window still displays it.
	-- Replace the panel's buffer first, then verify the old one can be wiped.
	local replacement_buffer = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(old_window, replacement_buffer)
	vim.api.nvim_buf_delete(old_buffer, { force = true })

	Assert(not vim.api.nvim_buf_is_valid(old_buffer), "Old dashboard buffer should be deleted")

	local reopened, reopen_err = pcall(Dashboard.Open, Root)
	Assert(reopened, "Dashboard should reopen after deletion: " .. tostring(reopen_err))
	Assert(vim.api.nvim_buf_is_valid(vim.api.nvim_get_current_buf()), "Current buffer should be valid after reopening")
	if vim.api.nvim_buf_is_valid(replacement_buffer) then
		pcall(vim.api.nvim_buf_delete, replacement_buffer, { force = true })
	end

	Remove_Test_Directory(Root)
end)

Test("Dashboard: create files and folders and cycle sort modes", function()
	local Root = Create_Test_Directory()
	local Dashboard = require("hypermax.dashboard")
	Assert(Dashboard.Open(Root), "Dashboard should open")

	local ok_file, file_path, file_err = Dashboard.Create("file", "src/created.c")
	Assert(ok_file, "Dashboard should create a file: " .. tostring(file_err))
	Assert(vim.fn.filereadable(file_path) == 1, "Dashboard should create a file")

	local ok_folder, folder_path, folder_err = Dashboard.Create("folder", "src/new_folder")
	Assert(ok_folder, "Dashboard should create a folder: " .. tostring(folder_err))
	Assert(vim.fn.isdirectory(folder_path) == 1, "Dashboard should create a folder")

	local old_mode = Dashboard.Get_State().sort_mode
	local next_mode = Dashboard.Cycle_Sort()
	Assert(Dashboard.Get_State().sort_mode ~= old_mode, "Sort key should cycle to the next sorting mode")
	Assert(type(next_mode) == "string", "Sort mode should be a name")
	Remove_Test_Directory(Root)
end)

Test("Dashboard: Git status is detected for a repository", function()
	if vim.fn.executable("git") ~= 1 then
		print("[SKIP] Git is not installed")
		return
	end
	local Root = Create_Test_Directory()
	local result = vim.fn.systemlist({ "git", "-C", Root, "init" })
	Assert(vim.v.shell_error == 0, "Could not initialize test Git repository: " .. table.concat(result, "\n"))
	local Dashboard = require("hypermax.dashboard")
	Assert(Dashboard.Open(Root), "Dashboard should open for Git project")
	local state = Dashboard.Get_State()
	Assert(state.git.available, "Dashboard should detect the Git repository")
	Assert(type(state.git.branch) == "string", "Dashboard should display a Git branch")
	Assert(next(state.git.statuses) ~= nil, "Git status should detect untracked project files")
	Remove_Test_Directory(Root)
end)

Test("Project metadata: basics.json records the entry file and main function", function()
	local Root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
	vim.fn.mkdir(Root .. "/src", "p")

	local main_file = assert(io.open(Root .. "/src/main.c", "w"))
	main_file:write("int main(void) { return 0; }\n")
	main_file:close()

	local ok, result = Project_Config.Create(Root, {
		name = "EntryPointTest",
		language = "c",
		manager = "native",
		entry_file = "src/main.c",
		entry_function = "main",
	})
	Assert(ok, "Could not create .hmc metadata: " .. tostring(result))

	local loaded, err = Project_Config.Load(Root)
	Assert(loaded ~= nil, "Could not reload .hmc metadata: " .. tostring(err))
	Assert(loaded.basics.project.entry_point.file == "src/main.c", "basics.json should record the entry file")
	Assert(loaded.basics.project.entry_point["function"] == "main", "basics.json should record the main function")

	-- The shared test registry is cleaned once at file exit.
	Remove_Test_Directory(Root)
end)

Test("Dashboard: opening an entry file keeps the sidebar visible", function()
	local Root = Create_Test_Directory()
	Assert(Dashboard.Open(Root), "Dashboard should open for a valid project")

	local state = Dashboard.Get_State()
	local panel_window = state.window
	local panel_buffer = state.buffer
	local entry_path = vim.fn.fnamemodify(Root .. "/src/main.c", ":p")
	local entry_line = state.line_by_path[entry_path]

	Assert(entry_line ~= nil, "Entry file should appear in the project tree")
	Assert(state.metadata.entry_file == "src/main.c", "Entry file should load from basics.json")
	Assert(state.metadata.entry_function == "main", "Entry function should load from basics.json")

	vim.api.nvim_set_current_win(panel_window)
	vim.api.nvim_win_set_cursor(panel_window, { entry_line, 0 })
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)

	local opened = vim.api.nvim_get_current_buf()
	Assert(vim.api.nvim_buf_is_valid(opened), "Opened entry buffer should be valid")
	Assert(vim.api.nvim_buf_get_name(opened) == entry_path, "Enter should open the configured entry file")
	Assert(vim.api.nvim_win_is_valid(panel_window), "Opening a file must not close the panel window")
	Assert(vim.api.nvim_win_get_buf(panel_window) == panel_buffer, "Opening a file must not replace the panel buffer")

	Remove_Test_Directory(Root)
end)

-- Dashboard rendering must not try to edit an unrelated,
-- nonmodifiable buffer.
Test("opening dashboard while current buffer is nonmodifiable is safe", function()
	local Root = Create_Test_Directory()

	vim.cmd("enew")
	local Original_Buffer = vim.api.nvim_get_current_buf()
	vim.bo[Original_Buffer].modifiable = false

	local ok, err = pcall(Dashboard.Open, Root)
	Flush_Scheduled_Callbacks()

	-- Restore the buffer so later tests can use it.
	if vim.api.nvim_buf_is_valid(Original_Buffer) then
		vim.bo[Original_Buffer].modifiable = true
	end

	Remove_Test_Directory(Root)

	Assert(ok, "Opening dashboard failed with a nonmodifiable buffer: " .. tostring(err))
end)

-- A dashboard must leave a valid current buffer and window.
Test("dashboard leaves a valid current window and buffer", function()
	local Root = Create_Test_Directory()

	local ok, err = pcall(Dashboard.Open, Root)
	Flush_Scheduled_Callbacks()

	Remove_Test_Directory(Root)

	Assert(ok, "Dashboard.Open failed: " .. tostring(err))

	local Window = vim.api.nvim_get_current_win()
	local Buffer = vim.api.nvim_get_current_buf()

	Assert(vim.api.nvim_win_is_valid(Window), "Current window is invalid")

	Assert_Valid_Buffer(Buffer)

	Assert(vim.api.nvim_win_get_buf(Window) == Buffer, "Current window is not displaying the current buffer")
end)

-- Opening the dashboard should be repeatable after another
-- buffer becomes current.
Test("dashboard can reopen after switching buffers", function()
	local Root = Create_Test_Directory()

	local ok1, err1 = pcall(Dashboard.Open, Root)
	Flush_Scheduled_Callbacks()

	Assert(ok1, "Initial dashboard open failed: " .. tostring(err1))

	vim.cmd("enew")

	local ok2, err2 = pcall(Dashboard.Open, Root)
	Flush_Scheduled_Callbacks()

	Remove_Test_Directory(Root)

	Assert(ok2, "Dashboard reopen failed: " .. tostring(err2))
	Assert_Valid_Buffer(vim.api.nvim_get_current_buf())
end)

-- Syntax-check the main dashboard and project modules.
Test("dashboard and project modules compile", function()
	local Files = {
		"lua/hypermax/dashboard.lua",
		"lua/hypermax/project.lua",
		"lua/hypermax/keymaps.lua",
		"lua/hypermax/init.lua",
	}

	for _, Path in ipairs(Files) do
		local Chunk, Err = loadfile(Path)

		Assert(Chunk ~= nil, Path .. " failed to compile: " .. tostring(Err))
	end
end)

-- Print a summary.
print("")
print("========== DASHBOARD RUNTIME TESTS ==========")
print("Passed: " .. Passed)
print("Failed: " .. Failed)
print("Total:  " .. (Passed + Failed))
print("=============================================")

if Failed > 0 then
	print("Failures:")

	for _, Failure in ipairs(Failures) do
		print("- " .. Failure.name .. ": " .. Failure.error)
	end

	error("Dashboard runtime tests failed: " .. Failed)
end

print("All dashboard runtime tests passed!")

Project_Config.global_path = original_global_path
pcall(vim.fn.delete, test_global_root, "rf")
