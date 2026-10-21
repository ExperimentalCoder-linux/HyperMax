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
    "lua/hypermax/project.lua",
    "lua/hypermax/settings.lua",
    "plugin/hypermax.lua",
    "tests/testlib.lua",
    "tests/test_languages.lua",
    "tests/test_managers.lua",
    "tests/test_layouts.lua",
    "tests/test_progress.lua",
    "tests/test_connections.lua",
    "tests/test_files.lua",
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
