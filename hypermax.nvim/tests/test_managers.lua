local Test = require("tests.testlib")
local Managers = require("hypermax.managers")
local Languages = require("hypermax.languages")

Test.Run("Known manager exists", function()
    Test.True(Managers.Exists("c", "native"))
    Test.True(Managers.Exists("c", "cmake"))
    Test.True(Managers.Exists("cpp", "make"))
end)

Test.Run("Unknown language and manager are handled", function()
    Test.False(Managers.Exists("hypermax_unknown", "native"))
    Test.Nil(Managers.Get("hypermax_unknown", "native"))
    Test.Nil(Managers.Get("c", "hypermax_unknown_manager"))
    Test.Nil(Managers.Is_Installed("hypermax_unknown", "native"))
    Test.Nil(Managers.Is_Installed("c", "hypermax_unknown_manager"))
end)

Test.Run("Unknown language receives a native fallback choice", function()
    local managers = Managers.Get_For_Language("hypermax_unknown")
    Test.Type("table", managers)
    Test.Type("table", managers.native)
    Test.Type("string", managers.native.name)
end)

Test.Run("Manager IDs are sorted and refer to real entries", function()
    for language_id in pairs(Managers.registry) do
        local ids = Managers.Get_IDs(language_id)
        local seen = {}
        for i, id in ipairs(ids) do
            Test.False(seen[id] == true, "Duplicate manager ID: " .. language_id .. "/" .. id)
            seen[id] = true
            if i > 1 then Test.True(ids[i - 1] <= id, "Manager IDs are not sorted") end
            Test.Not_Nil(Managers.Get(language_id, id))
        end
    end
end)

Test.Run("Every manager definition has a name", function()
    for language_id, managers in pairs(Managers.registry) do
        Test.Type("table", managers, language_id .. " manager group must be a table")
        for manager_id, manager in pairs(managers) do
            Test.Type("string", manager_id)
            Test.Type("table", manager, language_id .. "/" .. manager_id .. " must be a table")
            Test.Type("string", manager.name, language_id .. "/" .. manager_id .. " has no name")
            Test.True(manager.name ~= "", language_id .. "/" .. manager_id .. " has empty name")
            if manager.executable ~= nil then
                Test.Type("string", manager.executable, language_id .. "/" .. manager_id .. " executable must be string")
                Test.True(manager.executable ~= "", language_id .. "/" .. manager_id .. " executable is empty")
            end
        end
    end
end)

Test.Run("Manager choices contain the required fields", function()
    local choices = Managers.Get_Choices("c")
    Test.True(#choices > 0, "C should have manager choices")
    for _, choice in ipairs(choices) do
        Test.Type("string", choice.id)
        Test.Type("string", choice.name)
        Test.True(Managers.Exists("c", choice.id), "Choice references missing manager: " .. choice.id)
        Test.True(choice.installed == nil or type(choice.installed) == "boolean")
    end
end)

Test.Run("Language registry manager links agree with manager registry", function()
    for language_id, language in pairs(Languages.Get_All()) do
        Test.Equal(Managers.Get_For_Language(language_id), language.managers,
            "Mismatched managers for language " .. language_id)
    end
end)
