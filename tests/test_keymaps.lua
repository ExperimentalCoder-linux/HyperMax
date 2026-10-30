local Test = require("tests.testlib")
local Keymaps = require("hypermax.keymaps")

Test.Run("HyperMax default menu mapping does not replace a user mapping", function()
	local lhs = Keymaps.Get_Default_Menu_Mapping()
	vim.keymap.set("n", lhs, function() end, { desc = "User-owned mapping" })

	Keymaps.Setup()

	local mapping = vim.fn.maparg(lhs, "n", false, true)
	Test.Type("table", mapping)
	Test.Equal("User-owned mapping", mapping.desc)
	pcall(vim.keymap.del, "n", lhs)
end)

Test.Run("HyperMax installs a minimal default after the user mapping is removed", function()
	local lhs = Keymaps.Get_Default_Menu_Mapping()
	Keymaps.Setup()
	local rhs = vim.fn.maparg(lhs, "n")
	Test.True(type(rhs) == "string" and rhs:find("HyperMax%-Menu") ~= nil)
end)

Test.Run("HyperMax exposes namespaced Plug mappings", function()
	local mappings = Keymaps.Get_Plug_Mappings()
	Test.True(#mappings >= 20)
	Test.True(vim.fn.maparg("<Plug>(HyperMax-Tasks)", "n") ~= "")
	Test.True(vim.fn.maparg("<Plug>(HyperMax-Menu)", "n") ~= "")
end)

Test.Run("Disabling default keymaps removes only HyperMax-owned defaults", function()
	local Config = require("hypermax.config")
	local original_get = Config.get
	local lhs = Keymaps.Get_Default_Menu_Mapping()
	Config.get = function(key)
		if key == "default_keymaps" then return false end
		return original_get(key)
	end
	Keymaps.Refresh_Default_Mapping()
	Test.Equal("", vim.fn.maparg(lhs, "n"))
	Config.get = original_get
end)

Test.Run("Enabling default keymaps reinstalls the minimal workspace mapping", function()
	local Config = require("hypermax.config")
	local original_get = Config.get
	local lhs = Keymaps.Get_Default_Menu_Mapping()
	Config.get = function(key)
		if key == "default_keymaps" then return true end
		return original_get(key)
	end
	Keymaps.Refresh_Default_Mapping()
	local rhs = vim.fn.maparg(lhs, "n")
	Test.True(type(rhs) == "string" and rhs:find("HyperMax%-Menu") ~= nil)
	Config.get = original_get
end)

Test.Run("Disabling default keymaps preserves a user-owned mapping", function()
	local Config = require("hypermax.config")
	local original_get = Config.get
	local lhs = Keymaps.Get_Default_Menu_Mapping()
	vim.keymap.set("n", lhs, function() end, { desc = "User-owned mapping" })
	Config.get = function(key)
		if key == "default_keymaps" then return false end
		return original_get(key)
	end
	Keymaps.Refresh_Default_Mapping()
	local mapping = vim.fn.maparg(lhs, "n", false, true)
	Test.Equal("User-owned mapping", mapping.desc)
	Config.get = original_get
	pcall(vim.keymap.del, "n", lhs)
end)

Test.Run("HyperMax does not replace a user-owned Plug mapping", function()
	local lhs = "<Plug>(HyperMax-Tasks)"
	vim.keymap.set("n", lhs, function() end, { desc = "User-owned Plug mapping" })
	Keymaps.Setup()
	local mapping = vim.fn.maparg(lhs, "n", false, true)
	Test.Equal("User-owned Plug mapping", mapping.desc)
	pcall(vim.keymap.del, "n", lhs)
	Keymaps.Setup()
end)

Test.Run("HyperMax keymap module does not eagerly load feature modules", function()
	package.loaded["hypermax.settings"] = nil
	package.loaded["hypermax.project"] = nil
	package.loaded["hypermax.workspace"] = nil
	package.loaded["hypermax.flow"] = nil
	package.loaded["hypermax.keymaps"] = nil

	local loaded = require("hypermax.keymaps")
	Test.Type("table", loaded)
	Test.Nil(package.loaded["hypermax.settings"])
	Test.Nil(package.loaded["hypermax.project"])
	Test.Nil(package.loaded["hypermax.workspace"])
	Test.Nil(package.loaded["hypermax.flow"])
end)

return true
