local Test = require("tests.testlib")

Test.Run("Standard health module exposes check", function()
	local Health = require("hypermax.health")
	Test.Type("table", Health)
	Test.Type("function", Health.check)
end)

Test.Run("Health check reports through the Neovim health API", function()
	local Health = require("hypermax.health")
	local original_health = vim.health
	local original_loaded = vim.g.loaded_hypermax
	local calls = {}

	vim.health = {
		start = function(name) calls[#calls + 1] = { "start", name } end,
		ok = function(message) calls[#calls + 1] = { "ok", message } end,
		info = function(message) calls[#calls + 1] = { "info", message } end,
		warn = function(message) calls[#calls + 1] = { "warn", message } end,
		error = function(message) calls[#calls + 1] = { "error", message } end,
	}
	vim.g.loaded_hypermax = true

	local ok, err = pcall(Health.check)

	vim.health = original_health
	vim.g.loaded_hypermax = original_loaded

	Test.True(ok, tostring(err))
	Test.True(#calls > 0, "Expected the health check to report at least one result")
	Test.Equal("start", calls[1][1])
end)

return true
