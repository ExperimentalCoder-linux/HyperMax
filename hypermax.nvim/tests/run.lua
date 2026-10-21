-- Run from the repository root with Neovim --headless.
local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local Test = require("tests.testlib")

-- Test the test runner itself. These intentionally exercise failing assertions
-- inside pcall, so the test suite itself remains green when the helpers work.
Test.Run("Tester: true assertion accepts true", function()
    Test.True(true)
end)

Test.Run("Tester: false assertion accepts false", function()
    Test.False(false)
end)

Test.Run("Tester: nil assertion accepts nil", function()
    Test.Nil(nil)
end)

Test.Run("Tester: equality detects incorrect values", function()
    local ok = pcall(Test.Equal, "expected", "actual")
    Test.False(ok, "Test.Equal did not reject mismatched values")
end)

Test.Run("Tester: true assertion rejects false", function()
    local ok = pcall(Test.True, false)
    Test.False(ok, "Test.True did not reject false")
end)

Test.Run("Tester: false assertion rejects true", function()
    local ok = pcall(Test.False, true)
    Test.False(ok, "Test.False did not reject true")
end)

Test.Run("Tester: nil assertion rejects non-nil", function()
    local ok = pcall(Test.Nil, "not nil")
    Test.False(ok, "Test.Nil did not reject a string")
end)

Test.Run("Tester: error assertion catches thrown errors", function()
    local message = Test.Error(function() error("expected test error") end)
    Test.True(tostring(message):find("expected test error", 1, true) ~= nil)
end)

local suites = {
    "tests/test_languages.lua",
    "tests/test_managers.lua",
    "tests/test_layouts.lua",
    "tests/test_progress.lua",
    "tests/test_connections.lua",
    "tests/test_files.lua",
}

for _, suite in ipairs(suites) do
    local ok, err = xpcall(function() dofile(root .. "/" .. suite) end, debug.traceback)
    if not ok then
        Test.Run(suite .. " loads without a top-level error", function() error(err) end)
    end
end

local passed = Test.Finish()
if not passed then
    vim.cmd("cquit 1")
else
    vim.cmd("qa!")
end
