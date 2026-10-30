local Test = require("tests.testlib")
local Commands = require("hypermax.commands")

local function Fake_API()
	local function No_Op() end
	return {
		create_project = No_Op,
		list_projects = No_Op,
		open_last_project = No_Op,
		quick_create_project = No_Op,
		save_layout = No_Op,
		edit_layout = No_Op,
		load_layout = No_Op,
		list_layouts = No_Op,
		open_workspace = No_Op,
		open_palette = No_Op,
		open_tasks = No_Op,
		open_runs = No_Op,
		open_diagnostics = No_Op,
		open_history = No_Op,
		save_point = function() return true, { id = "test-save" } end,
		open_settings = No_Op,
		get_config = function() return {} end,
		open_tutorials = No_Op,
	}
end

local fake_api = Fake_API()
Commands.setup(fake_api)

Test.Run("HyperMax command completion lists root subcommands", function()
	local matches = Commands.complete("pro", "HyperMax pro", #"HyperMax pro")
	Test.True(vim.tbl_contains(matches, "project"))
	Test.False(vim.tbl_contains(matches, "layout"))
end)

Test.Run("HyperMax command completion lists nested project actions", function()
	local matches = Commands.complete("qui", "HyperMax project qui", #"HyperMax project qui")
	Test.Equal(1, #matches)
	Test.Equal("quick-create", matches[1])
end)

Test.Run("HyperMax command completion lists layout actions", function()
	local matches = Commands.complete("", "HyperMax layout ", #"HyperMax layout ")
	Test.True(vim.tbl_contains(matches, "save"))
	Test.True(vim.tbl_contains(matches, "edit"))
	Test.True(vim.tbl_contains(matches, "load"))
	Test.True(vim.tbl_contains(matches, "list"))
end)

Test.Run("HyperMax command completion lists workspace actions", function()
	local matches = Commands.complete("d", "HyperMax workspace d", #"HyperMax workspace d")
	Test.Equal(1, #matches)
	Test.Equal("diagnostics", matches[1])
end)


Test.Run("HyperMax command completion accepts the Ex command prefix", function()
	local matches = Commands.complete("pro", ":HyperMax pro", #":HyperMax pro")
	Test.True(vim.tbl_contains(matches, "project"))
end)

Test.Run("HyperMax command completion delegates directory arguments", function()
	local matches = Commands.complete("", "HyperMax project convert ", #"HyperMax project convert ")
	Test.Type("table", matches)
end)

Test.Run("HyperMax directory completion tolerates quoted paths with spaces", function()
	local matches = Commands.complete("~/Code/my project", 'HyperMax project convert "~/Code/my project"', #('HyperMax project convert "~/Code/my project"'))
	Test.Type("table", matches)
end)

Test.Run("HyperMax completion rejects bang syntax because the command does not support it", function()
	local matches = Commands.complete("pro", "HyperMax! pro", #"HyperMax! pro")
	Test.Equal(0, #matches)
end)

Test.Run("HyperMax command is the single global action command", function()
	local commands = vim.api.nvim_get_commands({ builtin = false })
	Test.True(commands.HyperMax ~= nil)
	Test.Nil(commands.HyperMaxCreate)
	Test.Nil(commands.HyperMaxWorkspace)
end)

Test.Run("HyperMax command callback dispatches parsed arguments", function()
	local called = false
	fake_api.create_project = function() called = true end
	vim.cmd("HyperMax project create")
	Test.True(called)
end)

Test.Run("HyperMax command without arguments opens the workspace", function()
	local called = false
	fake_api.open_workspace = function() called = true end
	Test.True(Commands.execute({}, {}))
	Test.True(called)
end)

Test.Run("HyperMax command dispatch calls the selected public action", function()
	local called = false
	fake_api.create_project = function() called = true end
	local ok = Commands.execute({ "project", "create" }, {})
	Test.True(ok)
	Test.True(called)
end)

Test.Run("HyperMax command dispatch reports unexpected arguments", function()
	local called = false
	fake_api.open_settings = function() called = true end
	local ok = Commands.execute({ "settings", "unexpected" }, {})
	Test.False(ok)
	Test.False(called)
end)

Test.Run("HyperMax command completion ignores unknown command paths", function()
	local matches = Commands.complete("x", "HyperMax unknown x", #"HyperMax unknown x")
	Test.Equal(0, #matches)
end)

pcall(vim.api.nvim_del_user_command, "HyperMax")

Test.Run("HyperMax does not overwrite an existing user command", function()
	vim.api.nvim_create_user_command("HyperMax", function() end, {
		nargs = "*",
		desc = "User-owned command",
	})

	-- Simulate a fresh module load while the user's command already exists.
	package.loaded["hypermax.commands"] = nil
	local Fresh_Commands = require("hypermax.commands")
	Test.False(Fresh_Commands.setup(fake_api))

	local registered = vim.api.nvim_get_commands({ builtin = false }).HyperMax
	Test.Equal("User-owned command", registered.desc)
	pcall(vim.api.nvim_del_user_command, "HyperMax")
end)

return true
