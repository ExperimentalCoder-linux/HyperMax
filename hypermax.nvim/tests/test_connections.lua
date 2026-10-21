local Test = require("tests.testlib")

local modules = {
    "hypermax.languages",
    "hypermax.managers",
    "hypermax.layouts",
    "hypermax.progress",
    "hypermax.config",
    "hypermax.settings",
    "hypermax.keymaps",
    "hypermax.project",
    "hypermax",
}

Test.Run("All core modules can be required", function()
    for _, module_name in ipairs(modules) do
        local ok, result = pcall(require, module_name)
        Test.True(ok, "Could not require " .. module_name .. ": " .. tostring(result))
        Test.Type("table", result, module_name .. " should return a table")
    end
end)

Test.Run("Language and manager registries are connected", function()
    local Languages = require("hypermax.languages")
    local Managers = require("hypermax.managers")
    for language_id, language in pairs(Languages.Get_All()) do
        if Managers.registry[language_id] then
            Test.Equal(Managers.Get_For_Language(language_id), language.managers,
                "Registry connection broken for " .. language_id)
            for manager_id in pairs(language.managers) do
                Test.True(Managers.Exists(language_id, manager_id),
                    "Missing manager connection: " .. language_id .. "/" .. manager_id)
            end
        else
            Test.Type("table", language.managers.native,
                "Fallback manager connection missing for " .. language_id)
        end
    end
end)

Test.Run("Project module has its required module connections", function()
    local Project = require("hypermax.project")
    Test.Type("table", Project)
    Test.Type("function", Project.Create)
    Test.Type("function", Project.Save_Layout)
    Test.Type("function", Project.List)
    Test.Type("function", Project.Open_Last)
    Test.Type("function", Project.Load_Layout)
end)

Test.Run("Public HyperMax API is connected", function()
    local HyperMax = require("hypermax")
    for _, name in ipairs({ "setup", "get_config", "get_version", "create_project", "save_layout", "open_settings" }) do
        Test.Type("function", HyperMax[name], "Missing public function: " .. name)
    end
    Test.Type("string", HyperMax.get_version())
    Test.Type("table", HyperMax.get_config())
end)
