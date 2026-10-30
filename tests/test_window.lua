-- Tests for the shared configurable floating-window placement helper.
local Test = require("tests.testlib")
local Config = require("hypermax.project_config")
local Window = require("hypermax.window")

local original_global_path = Config.global_path
local global_root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
Config.global_path = global_root .. "/hypermax/config.json"

local function Root()
	local root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
	vim.fn.mkdir(root, "p")
	local ok, err = Config.Create(root, { name = "WindowTest", language = "lua", manager = "native" })
	assert(ok, tostring(err))
	return root
end

Test.Run("Window placement reads the project setting and normalizes it", function()
	local root = Root()
	assert(Config.Save_Project_Settings(root, { context_position = "ne" }))
	Test.Equal("NE", Window.Get_Position(root))
	assert(Config.Save_Project_Settings(root, { context_position = "north-west" }))
	Test.Equal("NW", Window.Get_Position(root))
	assert(Config.Save_Project_Settings(root, { context_position = "south-east" }))
	Test.Equal("SE", Window.Get_Position(root))
	assert(Config.Save_Project_Settings(root, { context_position = "middle" }))
	Test.Equal("center", Window.Get_Position(root))
	assert(Config.Save_Project_Settings(root, { context_position = "invalid" }))
	Test.Equal("center", Window.Get_Position(root))
	pcall(vim.fn.delete, root, "rf")
end)

Test.Run("Window placement supports cardinal, corner and middle anchors", function()
	local root = Root()
	local columns, lines = vim.o.columns, vim.o.lines
	local positions = { "N", "S", "E", "W", "NE", "NW", "SE", "SW", "NS", "EW", "center" }
	for _, position in ipairs(positions) do
		assert(Config.Save_Project_Settings(root, { context_position = position }))
		local config = Window.Get_Config(40, 10, root)
		Test.True(config.row >= 0 and config.col >= 0, "Window coordinates must not be negative")
		Test.True(config.row + config.height <= lines, "Window must fit vertically")
		Test.True(config.col + config.width <= columns, "Window must fit horizontally")
	end
	assert(Config.Save_Project_Settings(root, { context_position = "NS" }))
	local north_south = Window.Get_Config(40, 10, root)
	assert(Config.Save_Project_Settings(root, { context_position = "EW" }))
	local east_west = Window.Get_Config(40, 10, root)
	Test.Equal(north_south.row, east_west.row)
	Test.Equal(north_south.col, east_west.col)
	pcall(vim.fn.delete, root, "rf")
end)

Config.global_path = original_global_path
pcall(vim.fn.delete, global_root, "rf")
