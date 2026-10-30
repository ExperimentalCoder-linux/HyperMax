-- Tests for pinned-task summaries shown persistently in editor winbars.
-- These tests control the starting winbar so results do not depend on the
-- user's Neovim configuration (which may define a custom %! expression).
local Test = require("tests.testlib")
local Project_Config = require("hypermax.project_config")
local Flow = require("hypermax.flow")
local Overlay = require("hypermax.task_overlay")

local original_global_path = Project_Config.global_path
local global_root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
Project_Config.global_path = global_root .. "/hypermax/config.json"

local function Cleanup(root)
	if root then pcall(vim.fn.delete, root, "rf") end
end

-- Give each test a real project buffer, then restore every editor resource even
-- when an assertion fails. This prevents a failed test from contaminating later
-- suites or changing the developer's own winbar.
local function With_Project_Buffer(callback)
	local previous_tab = vim.api.nvim_get_current_tabpage()
	local test_tab
	local window
	local previous_buffer
	local previous_winbar
	local root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
	local buffer

	local ok, err = xpcall(function()
		-- Use a full-width window independent of the layout left by earlier
		-- integration tests. The overlay must still show a useful title in narrow
		-- splits, but this test verifies the complete title when space permits.
		vim.cmd("tabnew")
		test_tab = vim.api.nvim_get_current_tabpage()
		window = vim.api.nvim_get_current_win()
		previous_buffer = vim.api.nvim_win_get_buf(window)
		previous_winbar = vim.wo[window].winbar

		vim.fn.mkdir(root .. "/src", "p")
		local source = assert(io.open(root .. "/src/main.lua", "w"))
		source:write("print('editing')\n")
		source:close()

		local created, create_error = Project_Config.Create(root, {
			name = "Pinned overlay test",
			language = "lua",
			manager = "native",
		})
		Test.True(created, tostring(create_error))

		buffer = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buffer, root .. "/src/main.lua")
		vim.api.nvim_win_set_buf(window, buffer)

		callback(root, window)
	end, debug.traceback)

	-- Restore every editor resource even when an assertion fails. This keeps
	-- the user's original tab, buffer and winbar intact between test suites.
	if window and vim.api.nvim_win_is_valid(window) then
		pcall(Overlay.Clear_Window, window)
		if previous_buffer and vim.api.nvim_buf_is_valid(previous_buffer) then
			pcall(vim.api.nvim_win_set_buf, window, previous_buffer)
		end
		if previous_winbar ~= nil then
			pcall(function() vim.wo[window].winbar = previous_winbar end)
		end
	end
	if buffer and vim.api.nvim_buf_is_valid(buffer) then
		pcall(vim.api.nvim_buf_delete, buffer, { force = true })
	end
	Cleanup(root)

	if test_tab and vim.api.nvim_tabpage_is_valid(test_tab) then
		pcall(vim.api.nvim_set_current_tabpage, test_tab)
		pcall(vim.cmd, "tabclose!")
	end
	if previous_tab and vim.api.nvim_tabpage_is_valid(previous_tab) then
		pcall(vim.api.nvim_set_current_tabpage, previous_tab)
	end

	if not ok then error(err) end
end

Test.Run("Pinned tasks appear in the editor winbar and disappear immediately when unpinned", function()
	With_Project_Buffer(function(root, window)
		-- Use a deterministic literal winbar. A user's custom %! expression is
		-- intentionally preserved by the overlay and must not affect this test.
		local base_winbar = "HyperMax test winbar"
		vim.wo[window].winbar = base_winbar

		local added, task = Flow.Add_Task(root, "Pinned overlay task", "Visible while editing", "high")
		Test.True(added, tostring(task))

		local pinned, result = Flow.Toggle_Task_Pinned(root, task.id)
		Test.True(pinned, tostring(result))

		local saved_data, load_error = Flow.Load(root)
		Test.True(saved_data ~= nil, tostring(load_error))
		Test.True(saved_data.tasks[1].pinned, "Pin state must be persisted before the UI is refreshed")

		local visible = vim.wo[window].winbar
		Test.True(visible:find("Pinned overlay task", 1, true) ~= nil,
			string.format(
				"Pinned title should be visible when space is available; winbar=%q, width=%d, root=%s",
				visible,
				vim.api.nvim_win_get_width(window),
				root
			))
		Test.True(visible:find("◆", 1, true) ~= nil,
			"Winbar should identify the pinned-task summary with its marker")
		Test.True(visible:find(base_winbar, 1, true) ~= nil,
			"The existing literal winbar should be preserved")

		local unpinned, unpin_result = Flow.Toggle_Task_Pinned(root, task.id)
		Test.True(unpinned, tostring(unpin_result))
		Test.Equal(base_winbar, vim.wo[window].winbar,
			"Original literal winbar should be restored after the last task is unpinned")
	end)
end)

Test.Run("Custom winbar expressions remain untouched when tasks are pinned", function()
	With_Project_Buffer(function(root, window)
		local custom_winbar = "%!toupper('custom winbar')"
		vim.wo[window].winbar = custom_winbar

		local added, task = Flow.Add_Task(root, "Expression-safe task", "Custom winbar test", "normal")
		Test.True(added, tostring(task))

		local pinned, result = Flow.Toggle_Task_Pinned(root, task.id)
		Test.True(pinned, tostring(result))
		Test.Equal(custom_winbar, vim.wo[window].winbar,
			"HyperMax must not replace a user-defined winbar expression")

		local unpinned, unpin_result = Flow.Toggle_Task_Pinned(root, task.id)
		Test.True(unpinned, tostring(unpin_result))
		Test.Equal(custom_winbar, vim.wo[window].winbar,
			"The custom winbar expression should remain intact after unpinning")
	end)
end)

Test.Run("User winbar changes made while tasks are pinned are preserved", function()
	With_Project_Buffer(function(root, window)
		local base_winbar = "Original user winbar"
		vim.wo[window].winbar = base_winbar

		local added, task = Flow.Add_Task(root, "User option task", "Winbar ownership test", "normal")
		Test.True(added, tostring(task))
		local pinned, pin_result = Flow.Toggle_Task_Pinned(root, task.id)
		Test.True(pinned, tostring(pin_result))

		local replacement = "User changed winbar"
		vim.wo[window].winbar = replacement
		local refreshed, refresh_error = Overlay.Refresh_Window(window)
		Test.True(refreshed, tostring(refresh_error))

		local unpinned, unpin_result = Flow.Toggle_Task_Pinned(root, task.id)
		Test.True(unpinned, tostring(unpin_result))
		Test.Equal(replacement, vim.wo[window].winbar,
			"Unpinning must restore the newest user winbar, not the stale original")
	end)
end)

Project_Config.global_path = original_global_path
Cleanup(global_root)
