local Test = require("tests.testlib")
local Config = require("hypermax.config")

Test.Run("Configuration defaults satisfy their declared schema", function()
	local valid, issues = Config.validate(Config.defaults)
	Test.True(valid, vim.inspect(issues))
end)

Test.Run("Configuration validation rejects invalid scalar types", function()
	local valid, issues = Config.validate({
		project_dir = 42,
		create_missing_dir = "yes",
	})
	Test.False(valid)
	Test.Equal(2, #issues)
end)

Test.Run("Configuration validates the default-keymap option", function()
	local valid = Config.validate({ default_keymaps = false })
	Test.True(valid)
	local invalid = Config.validate({ default_keymaps = "yes" })
	Test.False(invalid)
end)

Test.Run("Configuration validation checks favourite language arrays", function()
	local valid, issues = Config.validate({ favourite_languages = { "cpp", 42 } })
	Test.False(valid)
	Test.Equal(1, #issues)
end)

Test.Run("Configuration rejects sparse favourite language arrays", function()
	local valid, issues = Config.validate({ favourite_languages = { [1] = "cpp", [3] = "lua" } })
	Test.False(valid)
	Test.Equal(1, #issues)
end)

Test.Run("Configuration rejects blank required strings", function()
	local valid, issues = Config.validate({ project_dir = "   " })
	Test.False(valid)
	Test.Equal(1, #issues)
end)

Test.Run("Configuration allows intentionally empty optional strings", function()
	local valid, issues = Config.validate({ default_layout = "", last_project_path = "" })
	Test.True(valid, vim.inspect(issues))
end)

Test.Run("Configuration validation reports unknown option names", function()
	local valid, issues = Config.validate({ project_dri = "~/Code" })
	Test.False(valid)
	Test.Equal(1, #issues)
	Test.Equal("project_dri", issues[1].field)
end)

Test.Run("Configuration rejects unknown saved-setting updates", function()
	local ok, err = Config.set("project_dri", "~/Code")
	Test.False(ok)
	Test.True(type(err) == "string" and err:find("Unknown configuration field", 1, true) ~= nil)
end)

Test.Run("Configuration exposes schema metadata", function()
	local schema = Config.get_schema()
	Test.Type("table", schema)
	Test.Equal("string", schema.project_dir.type)
	Test.Equal("boolean", schema.show_progress.type)
	Test.Equal("table", schema.favourite_languages.type)
	Test.Equal("boolean", schema.default_keymaps.type)
	Test.True(Config.defaults.default_keymaps)
end)

return true
