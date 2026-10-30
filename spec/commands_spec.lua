package.path = table.concat({ "lua/?.lua", "lua/?/init.lua", "spec/?.lua", package.path }, ";")

local nvim = require("support.neovim")
local Commands = require("hypermax.commands")

local function Fake_API()
	return {
		create_project = function() end,
		list_projects = function() end,
		open_last_project = function() end,
		quick_create_project = function() end,
		save_layout = function() end,
		edit_layout = function() end,
		load_layout = function() end,
		list_layouts = function() end,
		open_workspace = function() end,
		open_palette = function() end,
		open_tasks = function() end,
		open_runs = function() end,
		open_diagnostics = function() end,
		open_history = function() end,
		save_point = function() return true, { id = "test-save" } end,
		open_settings = function() end,
		get_config = function() return {} end,
		open_tutorials = function() end,
	}
end

describe("HyperMax scoped command interface", function()
	before_each(function()
		nvim.commands.HyperMax = nil
		-- Commands keeps its own registration guard. Requiring the module again
		-- gives each spec a clean command tree without depending on Neovim.
		package.loaded["hypermax.commands"] = nil
		Commands = require("hypermax.commands")
	end)

	it("registers one :HyperMax command with completion", function()
		assert.is_true(Commands.setup(Fake_API()))
		assert.is_function(nvim.commands.HyperMax.callback)
		assert.is_function(nvim.commands.HyperMax.options.complete)
		assert.is_nil(nvim.commands.HyperMaxCreate)
	end)

	it("completes root and nested subcommands", function()
		Commands.setup(Fake_API())
		local root = Commands.complete("pro", ":HyperMax pro", #":HyperMax pro")
		local nested = Commands.complete("qui", "HyperMax project qui", #"HyperMax project qui")

		assert.is_true(vim.tbl_contains(root, "project"))
		assert.are.same({ "quick-create" }, nested)
	end)

	it("delegates path completion to Neovim", function()
		Commands.setup(Fake_API())
		local matches = Commands.complete("s", "HyperMax project convert s", #"HyperMax project convert s")

		assert.are.same({ "src/" }, matches)
	end)

	it("dispatches a selected command through the public API", function()
		local called = false
		local api = Fake_API()
		api.create_project = function() called = true end
		Commands.setup(api)

		local result = Commands.execute({ "project", "create" }, {})

		assert.is_true(result)
		assert.is_true(called)
	end)

	it("rejects unexpected positional arguments", function()
		local called = false
		local api = Fake_API()
		api.open_settings = function() called = true end
		Commands.setup(api)

		local result = Commands.execute({ "settings", "unexpected" }, {})

		assert.is_false(result)
		assert.is_false(called)
		assert.is_true(#nvim.notifications > 0)
	end)
end)
