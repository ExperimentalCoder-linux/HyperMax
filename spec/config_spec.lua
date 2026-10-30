package.path = table.concat({ "lua/?.lua", "lua/?/init.lua", "spec/?.lua", package.path }, ";")

require("support.neovim")

local Config = require("hypermax.config")

describe("HyperMax configuration schema", function()
	it("accepts the complete default configuration", function()
		local valid, issues = Config.validate(Config.defaults)

		assert.is_true(valid)
		assert.are.same({}, issues)
	end)

	it("rejects values with the wrong scalar type", function()
		local valid, issues = Config.validate({
			project_dir = 42,
			create_missing_dir = "yes",
		})

		assert.is_false(valid)
		assert.are.equal(2, #issues)
	end)

	it("rejects unknown option names instead of silently accepting typos", function()
		local valid, issues = Config.validate({ project_dri = "~/Code" })

		assert.is_false(valid)
		assert.are.equal(1, #issues)
		assert.are.equal("project_dri", issues[1].field)
	end)

	it("requires favourite languages to be a dense array of strings", function()
		local valid = Config.validate({ favourite_languages = { "cpp", "lua" } })
		local invalid_items = Config.validate({ favourite_languages = { "cpp", 42 } })
		local sparse = Config.validate({ favourite_languages = { [1] = "cpp", [3] = "lua" } })

		assert.is_true(valid)
		assert.is_false(invalid_items)
		assert.is_false(sparse)
	end)

	it("allows deliberately empty optional string settings", function()
		local valid, issues = Config.validate({
			default_layout = "",
			last_project_path = "",
		})

		assert.is_true(valid)
		assert.are.same({}, issues)
	end)

	it("returns a defensive copy of its schema", function()
		local schema = Config.get_schema()
		schema.project_dir.type = "number"

		assert.are.equal("string", Config.get_schema().project_dir.type)
	end)
end)
