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

Test.Run("HyperMax does not overwrite an existing user command", function()
	local ok, err = xpcall(function()
		-- The command created at the top of this suite is owned by HyperMax.
		-- Remove it explicitly and verify the namespace is clear before creating
		-- the simulated user command. A swallowed deletion error would make this
		-- test accidentally inspect HyperMax's own command instead.
		local commands_before = vim.api.nvim_get_commands({ builtin = false })
		if commands_before.HyperMax then
			vim.api.nvim_del_user_command("HyperMax")
		end
		Test.Nil(vim.api.nvim_get_commands({ builtin = false }).HyperMax,
			"Test setup must remove the original HyperMax command")

		vim.api.nvim_create_user_command("HyperMax", function() end, {
			nargs = "*",
			desc = "User-owned command",
		})

		-- Simulate a fresh module load while the user's command already exists.
		package.loaded["hypermax.commands"] = nil
		local Fresh_Commands = require("hypermax.commands")
		Test.False(Fresh_Commands.setup(fake_api))

		local registered = vim.api.nvim_get_commands({ builtin = false }).HyperMax
		Test.Not_Nil(registered)
		Test.Equal("User-owned command", registered.desc)

		-- Once the user removes the conflicting command, HyperMax can register
		-- its own command normally.
		vim.api.nvim_del_user_command("HyperMax")
		Test.True(Fresh_Commands.setup(fake_api))
		Test.Equal("HyperMax project and workspace commands",
			vim.api.nvim_get_commands({ builtin = false }).HyperMax.desc)
	end, debug.traceback)

	pcall(vim.api.nvim_del_user_command, "HyperMax")
	if not ok then error(err) end
end)

return true
