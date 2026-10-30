-- Tests for project-scoped diagnostics collection and quickfix item mapping.
local Test = require("tests.testlib")
local Config = require("hypermax.project_config")
local Diagnostics = require("hypermax.diagnostics")

local original_global_path = Config.global_path
local global_root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
Config.global_path = global_root .. "/hypermax/config.json"

local function Root()
	local root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
	vim.fn.mkdir(root, "p")
	local ok, err = Config.Create(root, { name = "DiagnosticsTest", language = "lua", manager = "native" })
	assert(ok, tostring(err))
	local file = assert(io.open(root .. "/main.lua", "w")); file:write("print('test')\n"); file:close()
	return root
end

local function Cleanup(root)
	if root then pcall(vim.fn.delete, root, "rf") end
end

Test.Run("Diagnostics count severity levels and convert positions to quickfix coordinates", function()
	local root = Root()
	local buffer = vim.fn.bufadd(root .. "/main.lua")
	vim.fn.bufload(buffer)
	local namespace = vim.api.nvim_create_namespace("HyperMaxDiagnosticsMappingTest")
	vim.diagnostic.set(namespace, buffer, {
		{ lnum = 0, col = 2, end_lnum = 0, end_col = 5, message = "error", severity = vim.diagnostic.severity.ERROR },
		{ lnum = 1, col = 0, message = "warning", severity = vim.diagnostic.severity.WARN },
		{ lnum = 2, col = 1, message = "hint", severity = vim.diagnostic.severity.HINT },
	}, {})

	local result = Diagnostics.Collect(root)
	Test.Equal(3, result.total)
	Test.Equal(1, result.errors)
	Test.Equal(1, result.warnings)
	Test.Equal(1, result.hints)
	Test.Equal(1, result.items[1].lnum)
	Test.Equal(3, result.items[1].col)
	Test.Equal(1, result.items[1].end_lnum)
	Test.Equal(6, result.items[1].end_col)
	Test.Equal("E", result.items[1].type)

	vim.diagnostic.reset(namespace, buffer)
	Cleanup(root)
end)

Test.Run("Diagnostics exclude files outside the project root boundary", function()
	local root = Root()
	local outside_root = vim.fn.fnamemodify(root .. "-outside", ":p")
	vim.fn.mkdir(outside_root, "p")
	local outside_path = outside_root .. "/outside.lua"
	local file = assert(io.open(outside_path, "w")); file:write("print('outside')\n"); file:close()
	local buffer = vim.fn.bufadd(outside_path)
	vim.fn.bufload(buffer)
	local namespace = vim.api.nvim_create_namespace("HyperMaxDiagnosticsBoundaryTest")
	vim.diagnostic.set(namespace, buffer, {
		{ lnum = 0, col = 0, message = "outside", severity = vim.diagnostic.severity.ERROR },
	}, {})

	local result = Diagnostics.Collect(root)
	Test.Equal(0, result.total, "A sibling directory with a matching prefix is not inside the project")
	vim.diagnostic.reset(namespace, buffer)
	Cleanup(outside_root)
	Cleanup(root)
end)


Test.Run("Diagnostics clear stale quickfix entries when the project has none", function()
	local root = Root()
	vim.fn.setqflist({}, " ", { items = { { filename = root .. "/old.lua", lnum = 1, col = 1, text = "stale" } } })
	local opened, result = Diagnostics.Open(root)
	Test.True(opened)
	Test.Equal(0, result.total)
	Test.Equal(0, #vim.fn.getqflist())
	local info = vim.fn.getqflist({ title = 1 })
	Test.Equal("HyperMax project diagnostics", info.title)
	Cleanup(root)
end)

Config.global_path = original_global_path
pcall(vim.fn.delete, global_root, "rf")
