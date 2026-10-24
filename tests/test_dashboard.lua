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
	local Path = vim.fn.tempname()
	vim.fn.mkdir(Path, "p")
	return vim.fn.fnamemodify(Path, ":p")
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
	Dashboard.Open(Root)
	vim.wait(100)

	local dashboard_buffer = vim.api.nvim_get_current_buf()

	Assert(vim.api.nvim_buf_is_valid(dashboard_buffer), "Dashboard buffer should initially be valid")

	-- Record what buffer we are testing.
	print("Dashboard buffer ID: " .. dashboard_buffer)
	print("Dashboard buffer name: " .. vim.api.nvim_buf_get_name(dashboard_buffer))

	-- Move to a separate buffer.
	local other_buffer = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_set_current_buf(other_buffer)

	Assert(vim.api.nvim_get_current_buf() ~= dashboard_buffer, "Should switch away from the dashboard buffer")

	-- Delete the dashboard buffer explicitly.
	vim.api.nvim_buf_delete(dashboard_buffer, { force = true })

	print("Dashboard buffer valid after deletion: " .. tostring(vim.api.nvim_buf_is_valid(dashboard_buffer)))

	Assert(not vim.api.nvim_buf_is_valid(dashboard_buffer), "Old dashboard buffer should be deleted")

	-- Reopen the dashboard.
	local ok, err = pcall(Dashboard.Open, Root)

	Assert(ok, "Dashboard should reopen after deletion: " .. tostring(err))

	Assert(vim.api.nvim_buf_is_valid(vim.api.nvim_get_current_buf()), "Current buffer should be valid after reopening")
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
