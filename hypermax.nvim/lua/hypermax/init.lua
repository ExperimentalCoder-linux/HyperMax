local Keymaps = require("hypermax.keymaps")
local Layouts = require("hypermax.layouts")
local Config = require("hypermax.config")
local Project = require("hypermax.project")
local Settings = require("hypermax.settings")

local HyperMax = {}
local Is_Setup = false

HyperMax.version = "0.2.0"

local function Register_Commands()
	local commands = {
		"HyperMaxCreate",
		"HyperMaxSaveLayout",
		"HyperMaxConfig",
		"HyperMaxSettings",
	}

	for _, command in ipairs(commands) do
		pcall(vim.api.nvim_del_user_command, command)
	end

	vim.api.nvim_create_user_command("HyperMaxCreate", function()
		Project.Create(Config.options)
	end, {
		desc = "Create a project with HyperMax",
	})

	vim.api.nvim_create_user_command("HyperMaxSaveLayout", function()
		Project.Save_Layout()
	end, {
		desc = "Save the current directory as a HyperMax layout",
	})

	vim.api.nvim_create_user_command("HyperMaxConfig", function()
		vim.print(Config.options)
	end, {
		desc = "Display HyperMax configuration",
	})

	vim.api.nvim_create_user_command("HyperMaxSettings", function()
		Settings.Open()
	end, {
		desc = "Open HyperMax settings",
	})
end

function HyperMax.setup(options)
	-- Do not reload persisted/default settings when the runtime loader calls
	-- setup() after the user's init.lua has already configured HyperMax.
	if not Is_Setup then
		Config.setup(options)
		Register_Commands()
		Keymaps.Setup(Project, Settings, Layouts)
		Is_Setup = true
	elseif options ~= nil then
		Config.setup(options)
	end
	return HyperMax
end
function HyperMax.get_config()
	return Config.options
end

function HyperMax.get_version()
	return HyperMax.version
end

function HyperMax.create_project()
	Project.Create(Config.options)
end

function HyperMax.save_layout()
	Project.Save_Layout()
end

function HyperMax.open_settings()
	Settings.Open()
end

return HyperMax
