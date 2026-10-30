local Test = require("tests.testlib")

Test.Run("Public module can be required without loading feature modules", function()
	local HyperMax = require("hypermax")
	Test.Type("table", HyperMax)
	Test.Nil(package.loaded["hypermax.project"])
	Test.Nil(package.loaded["hypermax.dashboard"])
	Test.Nil(package.loaded["hypermax.workspace"])
	Test.Nil(package.loaded["hypermax.flow"])
	Test.Nil(package.loaded["hypermax.git"])
	Test.Nil(package.loaded["hypermax.history"])
	Test.Nil(package.loaded["hypermax.tutorial"])
end)

Test.Run("Public API reports the current semantic version", function()
	local HyperMax = require("hypermax")
	Test.True(HyperMax.get_version():match("^%d+%.%d+%.%d+$") ~= nil)
end)

Test.Run("Public setup configures without initializing runtime features", function()
	local HyperMax = require("hypermax")
	local result = HyperMax.setup({
		project_dir = vim.fn.tempname(),
		default_language = "cpp",
	})

	Test.Equal(HyperMax, result)
	Test.False(HyperMax.is_initialized())
	Test.Nil(package.loaded["hypermax.project"])
	Test.Nil(package.loaded["hypermax.dashboard"])
	Test.Nil(package.loaded["hypermax.workspace"])
end)

Test.Run("Keymap registration module has no eager feature imports", function()
	require("hypermax.keymaps")
	Test.Nil(package.loaded["hypermax.settings"])
	Test.Nil(package.loaded["hypermax.layouts"])
	Test.Nil(package.loaded["hypermax.project"])
end)

return true
