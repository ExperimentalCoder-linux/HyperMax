-- Runtime tests for HyperMax workspace and flow screens.
local Test = require("tests.testlib")
local Config = require("hypermax.project_config")
local Workspace = require("hypermax.workspace")
local Flow = require("hypermax.flow")

local original_global_path = Config.global_path
local global_root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
Config.global_path = global_root .. "/hypermax/config.json"

local function Root()
	local root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
	vim.fn.mkdir(root .. "/src", "p")
	local file = assert(io.open(root .. "/src/main.lua", "w"))
	file:write("-- TODO: write application entry point\n")
	file:close()
	local ok, err = Config.Create(root, { name = "WorkspaceTest", language = "lua", manager = "native" })
	assert(ok, tostring(err))
	return root
end

local function Cleanup(root)
	Workspace.Close()
	Flow.Close()
	if root then pcall(vim.fn.delete, root, "rf") end
end

Test.Run("Workspace home opens and renders project health", function()
	local root = Root()
	local ok = Workspace.Open(root)
	Test.True(ok)
	local state = Workspace.Get_State()
	Test.Equal(vim.fn.fnamemodify(root, ":p"):gsub("/+$", ""), state.root)
	Test.True(vim.api.nvim_buf_is_valid(state.buffer))
	local lines = vim.api.nvim_buf_get_lines(state.buffer, 0, -1, false)
	local content = table.concat(lines, "\n")
	Test.True(content:find("HYPERMAX", 1, true) ~= nil)
	Test.True(content:find("WorkspaceTest", 1, true) ~= nil)
	Test.True(content:find("Task board", 1, true) ~= nil)
	Test.True(content:find("RECENT PROJECTS", 1, true) ~= nil)
	Test.Equal(vim.fn.fnamemodify(root, ":p"):gsub("/+$", ""), state.recent_projects[1].path)
	local has_enter_action = false
	for _, entry in ipairs(vim.api.nvim_buf_get_keymap(state.buffer, "n")) do
		if entry.lhs == "<CR>" and (entry.desc or ""):find("recent project", 1, true) then has_enter_action = true end
	end
	Test.True(has_enter_action, "Recent project rows should be openable from the workspace")
	Cleanup(root)
end)

Test.Run("Task board screen renders an empty project board", function()
	local root = Root()
	Test.True(Flow.Open_Tasks(root))
	local state = Flow.Get_State()
	Test.True(vim.api.nvim_buf_is_valid(state.buffer))
	local content = table.concat(vim.api.nvim_buf_get_lines(state.buffer, 0, -1, false), "\n")
	Test.True(content:find("PLAN", 1, true) ~= nil)
	Test.True(content:find("TODO", 1, true) ~= nil)
	Cleanup(root)
end)

Test.Run("Run configuration screen renders and exposes project runner actions", function()
	local root = Root()
	local ok, runner = Flow.Add_Runner(root, "Syntax check", "luac -p src/main.lua", ".")
	Test.True(ok, tostring(runner))
	Test.True(Flow.Open_Runners(root))
	local state = Flow.Get_State()
	local content = table.concat(vim.api.nvim_buf_get_lines(state.buffer, 0, -1, false), "\n")
	Test.True(content:find("BUILD", 1, true) ~= nil)
	Test.True(content:find("Syntax check", 1, true) ~= nil)
	Cleanup(root)
end)

Test.Run("Workspace diagnostics are scoped to the project and open quickfix", function()
	local root = Root()
	local file_path = root .. "/src/main.lua"
	local buffer = vim.fn.bufadd(file_path)
	vim.fn.bufload(buffer)
	local namespace = vim.api.nvim_create_namespace("HyperMaxWorkspaceTest")
	vim.diagnostic.set(namespace, buffer, {
		{ lnum = 0, col = 0, message = "test diagnostic", severity = vim.diagnostic.severity.ERROR },
	}, {})
	local outside_root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
	vim.fn.mkdir(outside_root, "p")
	local outside_path = outside_root .. "/outside.lua"
	local outside_file = assert(io.open(outside_path, "w"))
	outside_file:write("-- outside project\n")
	outside_file:close()
	local outside_buffer = vim.fn.bufadd(outside_path)
	vim.fn.bufload(outside_buffer)
	vim.diagnostic.set(namespace, outside_buffer, {
		{ lnum = 0, col = 0, message = "unrelated diagnostic", severity = vim.diagnostic.severity.WARN },
	}, {})
	Test.True(Workspace.Open(root))
	Test.True(Workspace.Diagnostics(root))
	local quickfix = vim.fn.getqflist({ title = 1, items = 1 })
	Test.Equal("HyperMax project diagnostics", quickfix.title)
	Test.Equal(1, #quickfix.items, "Diagnostics outside this project must be excluded")
	Test.Equal("test diagnostic", quickfix.items[1].text)
	Test.Equal(nil, Workspace.Get_State().window, "Opening diagnostics should dismiss the workspace float")
	vim.diagnostic.reset(namespace, buffer)
	vim.diagnostic.reset(namespace, outside_buffer)
	pcall(vim.fn.delete, outside_root, "rf")
	Cleanup(root)
end)

Test.Run("Workspace command palette exposes core project actions", function()
	local root = Root()
	local ok = Workspace.Open(root)
	Test.True(ok)
	local state = Workspace.Get_State()
	local keys = vim.api.nvim_buf_get_keymap(state.buffer, "n")
	local palette_mapped = false
	for _, entry in ipairs(keys) do
		if (entry.desc or ""):find("command palette", 1, true) then palette_mapped = true end
	end
	Test.True(palette_mapped, "Workspace should expose its palette shortcut")
	Cleanup(root)
end)

Config.global_path = original_global_path
pcall(vim.fn.delete, global_root, "rf")
