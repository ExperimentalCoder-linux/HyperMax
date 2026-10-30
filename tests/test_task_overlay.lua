-- Tests for pinned-task summaries shown persistently in editor winbars.
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

Test.Run("Pinned tasks appear in the editor winbar and disappear immediately when unpinned", function()
	local root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
	vim.fn.mkdir(root .. "/src", "p")
	local source = assert(io.open(root .. "/src/main.lua", "w"))
	source:write("print('editing')\n")
	source:close()
	local created, create_error = Project_Config.Create(root, { name = "Pinned overlay test", language = "lua", manager = "native" })
	Test.True(created, tostring(create_error))

	local window = vim.api.nvim_get_current_win()
	local previous_buffer = vim.api.nvim_win_get_buf(window)
	local previous_winbar = vim.wo[window].winbar
	local buffer = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(buffer, root .. "/src/main.lua")
	vim.api.nvim_win_set_buf(window, buffer)

	local added, task = Flow.Add_Task(root, "Pinned overlay task", "Visible while editing", "high")
	Test.True(added, tostring(task))
	local pinned, result = Flow.Toggle_Task_Pinned(root, task.id)
	Test.True(pinned, tostring(result))
	local visible = vim.wo[window].winbar
	Test.True(visible:find("Pinned overlay task", 1, true) ~= nil, "Pinned title should be visible in the editor winbar")
	Test.True(visible:find("PINNED", 1, true) ~= nil, "Winbar should identify the pinned-task summary")

	local unpinned, unpin_result = Flow.Toggle_Task_Pinned(root, task.id)
	Test.True(unpinned, tostring(unpin_result))
	Test.Equal(previous_winbar, vim.wo[window].winbar, "Original winbar should be restored after the last task is unpinned")

	vim.api.nvim_win_set_buf(window, previous_buffer)
	pcall(vim.api.nvim_buf_delete, buffer, { force = true })
	Cleanup(root)
end)

Project_Config.global_path = original_global_path
Cleanup(global_root)
