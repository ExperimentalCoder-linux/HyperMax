-- =========================================================
-- HYPERMAX TEST RUNNER
-- =========================================================
package.path = "./tests/?.lua;" .. package.path
local source = debug.getinfo(1, "S").source

if source:sub(1, 1) == "@" then
	source = source:sub(2)
end

local test_directory = vim.fs.dirname(vim.fn.fnamemodify(source, ":p"))
local plugin_root = vim.fs.dirname(test_directory)

-- Make the plugin and test helper files discoverable.
vim.opt.rtp:prepend(plugin_root)

package.path = table.concat({
	plugin_root .. "/?.lua",
	plugin_root .. "/?/init.lua",
	package.path,
}, ";")

-- Tests expect the repository root as the working directory.
vim.fn.chdir(plugin_root)

local Test = require("tests.testlib")

-- The test suite creates and opens temporary projects. Keep all registry
-- writes in a temporary directory so running tests cannot alter a developer's
-- real HyperMax project list or last-opened project.
local Project_Config = require("hypermax.project_config")
local original_project_global_path = Project_Config.global_path
local project_test_root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
Project_Config.global_path = project_test_root .. "/hypermax/config.json"

-- =========================================================
-- TEST SUITES
-- =========================================================

local test_files = {
	"tests/test_file.lua",
	"tests/test_connections.lua",
	"tests/test_languages.lua",
	"tests/test_managers.lua",
	"tests/test_layout.lua",
	"tests/test_progress.lua",
	"tests/test_filesystem.lua",
	"tests/test_project_lifecycle.lua",
	"tests/test_git.lua",
	"tests/test_flow.lua",
	"tests/test_workspace.lua",
	"tests/test_dashboard.lua",
	"tests/test_dashboard_deep.lua",
}

-- =========================================================
-- EXECUTE EACH TEST SUITE
-- =========================================================

print("")
print("[INFO] HyperMax repository: " .. plugin_root)
print("[INFO] Starting health checks...")
print("")

for _, relative_path in ipairs(test_files) do
	local full_path = plugin_root .. "/" .. relative_path
	local chunk, load_error = loadfile(full_path)

	if not chunk then
		Test.Run("Load " .. relative_path, function()
			error("Could not load test file:\n" .. tostring(load_error))
		end)
	else
		local ok, err = xpcall(chunk, debug.traceback)

		if not ok then
			Test.Run("Execute " .. relative_path, function()
				error("Test file crashed:\n" .. tostring(err))
			end)
		end
	end
end

-- Restore the caller's registry setting and remove the temporary test index.
Project_Config.global_path = original_project_global_path
pcall(vim.fn.delete, project_test_root, "rf")

-- =========================================================
-- FINAL RESULT AND PROCESS EXIT CODE
-- =========================================================

local success = Test.Finish()

if success then
	vim.cmd("qa!")
else
	-- A failed health check must return a non-zero exit code.
	vim.cmd("cquit 1")
end
