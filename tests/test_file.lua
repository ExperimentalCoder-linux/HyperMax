local Test = require("tests.testlib")
local uv = vim.uv or vim.loop
local root = vim.fn.getcwd()

local required_files = {
	"lua/hypermax/init.lua",
	"lua/hypermax/config.lua",
	"lua/hypermax/check_list.txt",
	"lua/hypermax/keymaps.lua",
	"lua/hypermax/layouts.lua",
	"lua/hypermax/layouts.json",
	"lua/hypermax/languages.lua",
	"lua/hypermax/managers.lua",
	"lua/hypermax/progress.lua",
	"lua/hypermax/filesystem.lua",
	"lua/hypermax/git.lua",
	"lua/hypermax/project.lua",
	"lua/hypermax/settings.lua",
	"plugin/hypermax.lua",
	"tests/testlib.lua",
	"tests/test_dashboard.lua",
	"tests/test_dashboard_deep.lua",
	"tests/test_filesystem.lua",
	"tests/test_git.lua",
	"tests/test_languages.lua",
	"tests/test_managers.lua",
	"tests/test_layout.lua",
	"tests/test_progress.lua",
	"tests/test_connections.lua",
	"tests/test_file.lua",
	"tests/run.lua",
}

Test.Run("Every required repository file exists", function()
	for _, relative in ipairs(required_files) do
		local full_path = root .. "/" .. relative
		Test.Not_Nil(uv.fs_stat(full_path), "Missing required file: " .. relative)
	end
end)

Test.Run("Required Lua files exist and compile without syntax errors", function()
	for _, relative in ipairs(required_files) do
		if relative:match("%.lua$") then
			local stat = uv.fs_stat(root .. "/" .. relative)
			Test.Not_Nil(stat, "Missing Lua file: " .. relative)
			Test.Equal("file", stat.type, "Expected regular file: " .. relative)
			local chunk, syntax_error = loadfile(root .. "/" .. relative)
			Test.Not_Nil(chunk, "Lua syntax error in " .. relative .. ": " .. tostring(syntax_error))
		end
	end
end)

Test.Run("Bundled layouts JSON exists and decodes", function()
	local path = root .. "/lua/hypermax/layouts.json"
	local file = io.open(path, "r")
	Test.Not_Nil(file, "Could not open layouts.json")
	local contents = file:read("*a")
	file:close()
	local ok, decoded = pcall(vim.json.decode, contents)
	Test.True(ok, "layouts.json is invalid JSON: " .. tostring(decoded))
	Test.Type("table", decoded)
	Test.Type("table", decoded.layouts)
end)

local Test = require("testlib")
local Dashboard = require("hypermax.dashboard")

local Root = vim.fn.getcwd()

Test.Run("Dashboard: opening dashboard is safe", function()
	Test.Not_Nil(Dashboard, "Dashboard module should load")
	Test.Type("function", Dashboard.Open, "Dashboard.Open should exist")

	local ok, err = pcall(Dashboard.Open, Root)

	Test.True(ok, "Opening dashboard should not raise an error: " .. tostring(err))
end)

Test.Run("Dashboard: opening dashboard twice is safe", function()
	local ok, err = pcall(Dashboard.Open, Root)
	Test.True(ok, "First open failed: " .. tostring(err))

	vim.wait(100)

	ok, err = pcall(Dashboard.Open, Root)
	Test.True(ok, "Second open failed: " .. tostring(err))
end)

Test.Run("Dashboard: opening dashboard with nonmodifiable buffer is safe", function()
	vim.cmd("enew")
	vim.bo.modifiable = false

	local ok, err = pcall(Dashboard.Open, Root)

	Test.True(ok, "Dashboard should handle a nonmodifiable buffer: " .. tostring(err))

	vim.bo.modifiable = true
end)

Test.Run("Dashboard: current buffer remains valid", function()
	local buffer = vim.api.nvim_get_current_buf()

	Test.True(vim.api.nvim_buf_is_valid(buffer), "Current buffer should be valid after opening dashboard")
end)

Test.Run("Dashboard: current window remains valid", function()
	local window = vim.api.nvim_get_current_win()

	Test.True(vim.api.nvim_win_is_valid(window), "Current window should be valid after opening dashboard")
end)

Test.Run("Dashboard: dashboard can reopen after switching buffers", function()
	vim.cmd("enew")

	local ok, err = pcall(Dashboard.Open, Root)

	Test.True(ok, "Dashboard should reopen after switching buffers: " .. tostring(err))
end)

Test.Run("Dashboard: dashboard source files compile", function()
	local files = {
		"lua/hypermax/dashboard.lua",
		"lua/hypermax/project.lua",
		"lua/hypermax/keymaps.lua",
		"lua/hypermax/init.lua",
	}

	for _, path in ipairs(files) do
		local file = io.open(path, "r")

		Test.Not_Nil(file, "Could not open " .. path)

		local source = file:read("*a")
		file:close()

		local chunk, err = loadstring(source, "@" .. path)

		Test.Not_Nil(chunk, "Lua syntax error in " .. path .. ": " .. tostring(err))
	end
end)
