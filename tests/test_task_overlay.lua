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
	local window = vim.api.nvim_get_current_win()
	local previous_buffer = vim.api.nvim_win_get_buf(window)
	local previous_winbar = vim.wo[window].winbar
	local root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
	local buffer

	local ok, err = xpcall(function()
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

	-- Clear HyperMax's ownership before restoring the exact user's settings.
	pcall(Overlay.Clear_Window, window)
	if vim.api.nvim_win_is_valid(window) then
		pcall(vim.api.nvim_win_set_buf, window, previous_buffer)
		pcall(function() vim.wo[window].winbar = previous_winbar end)
	end
	if buffer and vim.api.nvim_buf_is_valid(buffer) then
		pcall(vim.api.nvim_buf_delete, buffer, { force = true })
	end
	Cleanup(root)

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

		local visible = vim.wo[window].winbar
		Test.True(visible:find("Pinned overlay task", 1, true) ~= nil,
			"Pinned title should be visible in the editor winbar")
		Test.True(visible:find("PINNED", 1, true) ~= nil,
			"Winbar should identify the pinned-task summary")
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

Project_Config.global_path = original_global_path
Cleanup(global_root)
