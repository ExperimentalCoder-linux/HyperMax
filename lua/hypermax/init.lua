local Keymaps = require("hypermax.keymaps")
local Layouts = require("hypermax.layouts")
local Config = require("hypermax.config")
local Project = require("hypermax.project")
local Settings = require("hypermax.settings")

local HyperMax = {}

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
	Config.setup(options)
	Register_Commands()
	Keymaps.Setup(Project, Settings, Layouts)
	-- Automatically open the dashboard when Neovim starts
	-- inside a HyperMax project, unless a file was specified.
	vim.api.nvim_create_autocmd("VimEnter", {
		group = vim.api.nvim_create_augroup("HyperMaxDashboard", { clear = true }),
		once = true,
		callback = function()
			if vim.fn.argc() > 0 then
				return
			end

			local Dashboard = require("hypermax.dashboard")
			local root = vim.fn.getcwd()

			if Dashboard.Is_Project(root) then
				Dashboard.Open(root)
			end
		end,
	})

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
