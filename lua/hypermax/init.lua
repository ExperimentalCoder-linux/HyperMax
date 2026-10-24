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
	-- Always open the dashboard when starting inside a HyperMax project.
	vim.api.nvim_create_autocmd("VimEnter", {
		group = vim.api.nvim_create_augroup("HyperMaxDashboard", {
			clear = true,
		}),
		once = true,
		callback = function()
			local Dashboard = require("hypermax.dashboard")

			-- First check the current working directory.
			local root = Dashboard.Find_Project_Root(vim.fn.getcwd())

			-- If needed, check the first file supplied to Neovim.
			if not root and vim.fn.argc() > 0 then
				root = Dashboard.Find_Project_Root(vim.fn.argv(0))
			end

			if root then
				vim.cmd("tcd " .. vim.fn.fnameescape(root))
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
