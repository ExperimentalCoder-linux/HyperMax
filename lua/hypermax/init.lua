local Keymaps = require("hypermax.keymaps")
local Layouts = require("hypermax.layouts")
local Config = require("hypermax.config")
local Project = require("hypermax.project")
local Settings = require("hypermax.settings")
local Workspace = require("hypermax.workspace")
local Flow = require("hypermax.flow")
local Tutorial = require("hypermax.tutorial")

local HyperMax = {}

HyperMax.version = "0.6.0"

local function Register_Commands()
	local commands = {
		"HyperMaxCreate",
		"HyperMaxSaveLayout",
		"HyperMaxLayoutEdit",
		"HyperMaxConfig",
		"HyperMaxSettings",
		"HyperMaxWorkspace",
		"HyperMaxPalette",
		"HyperMaxTasks",
		"HyperMaxRuns",
		"HyperMaxDiagnostics",
		"HyperMaxHistory",
		"HyperMaxSavePoint",
		"HyperMaxTutorial",
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
		desc = "Create a reusable layout draft from the current directory",
	})

	vim.api.nvim_create_user_command("HyperMaxLayoutEdit", function()
		Project.Edit_Layout()
	end, {
		desc = "Edit an existing HyperMax layout in a temporary file",
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

	vim.api.nvim_create_user_command("HyperMaxWorkspace", function()
		Workspace.Open()
	end, { desc = "Open the HyperMax workspace home" })
	vim.api.nvim_create_user_command("HyperMaxPalette", function()
		Workspace.Palette()
	end, { desc = "Open the HyperMax command palette" })
	vim.api.nvim_create_user_command("HyperMaxTasks", function()
		Flow.Open_Tasks()
	end, { desc = "Open the current project's task board" })
	vim.api.nvim_create_user_command("HyperMaxRuns", function()
		Flow.Open_Runners()
	end, { desc = "Manage project run configurations" })
	vim.api.nvim_create_user_command("HyperMaxDiagnostics", function()
		Workspace.Diagnostics()
	end, { desc = "Show diagnostics scoped to the current project" })
	vim.api.nvim_create_user_command("HyperMaxHistory", function()
		require("hypermax.history").Open()
	end, { desc = "Browse project save points and roll back" })
	vim.api.nvim_create_user_command("HyperMaxSavePoint", function()
		local ok, result = require("hypermax.history").Save(nil, "hard")
		vim.notify(ok and ("HyperMax: Hard save created: " .. result.id) or ("HyperMax: " .. tostring(result)),
			ok and vim.log.levels.INFO or vim.log.levels.ERROR)
	end, { desc = "Create a hard project save point" })
	vim.api.nvim_create_user_command("HyperMaxTutorial", function()
		Tutorial.Open_Menu()
	end, { desc = "Open the Essentials and Advanced tutorials" })
end

function HyperMax.setup(options)
	Config.setup(options)
	Register_Commands()
	Keymaps.Setup(Project, Settings, Layouts)
	require("hypermax.task_overlay").Setup()
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
	-- This marker is stored under stdpath('data') and is not tied to the
	-- plugin version, so installing an update never repeats first-run setup.
	Tutorial.Setup_Startup()
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

function HyperMax.open_workspace()
	Workspace.Open()
end

function HyperMax.open_palette()
	Workspace.Palette()
end

function HyperMax.open_tasks()
	Flow.Open_Tasks()
end

function HyperMax.open_runs()
	Flow.Open_Runners()
end

function HyperMax.open_diagnostics()
	Workspace.Diagnostics()
end

function HyperMax.open_history()
	return require("hypermax.history").Open()
end

function HyperMax.open_tutorials()
	return Tutorial.Open_Menu()
end

function HyperMax.save_point()
	return require("hypermax.history").Save(nil, "hard")
end

return HyperMax
