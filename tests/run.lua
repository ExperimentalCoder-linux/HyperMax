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
