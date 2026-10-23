local Settings = require("hypermax.settings")
local Layouts = require("hypermax.layouts")
local Config = require("hypermax.config")

local Keymaps = {}

local function Run_Health_Check()
	-- Find the plugin root from this file's location.
	local source = debug.getinfo(1, "S").source:sub(2)
	local plugin_root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))

	-- Run the tests in a separate, clean Neovim process.
	vim.cmd("botright new")

	vim.fn.termopen({
		vim.v.progpath,
		"--headless",
		"-u",
		"NONE",
		"-c",
		"cd " .. vim.fn.fnameescape(plugin_root),
		"-c",
		"set rtp+=.",
		"-c",
		"luafile tests/run.lua",
		"-c",
		"qa!",
	})
end

local function Map(key, action, description)
	vim.keymap.set("n", "<leader>+" .. key, action, {
		desc = "HyperMax: " .. description,
		silent = true,
	})
end

function Keymaps.Setup(Project, Settings, Layouts)
	-- Main menu
	Map("+", function()
		vim.ui.select({
			"Projects",
			"Settings",
			"Load layout",
			"Save current project as layout",
			"Open last project",
			"Health Check",
		}, {
			prompt = "HyperMax",
		}, function(choice)
			if choice == "Projects" then
				Project.Create()
			elseif choice == "Settings" then
				Settings.Open()
			elseif choice == "Load layout" then
				Project.Load_Layout()
			elseif choice == "Save current project as layout" then
				Project.Save_Layout()
			elseif choice == "Open last project" then
				Project.Open_Last()
			elseif choice == "Health Check" then
				Run_Health_Check()
			end
		end)
	end, "Open menu")

	-- Individual shortcuts
	Map("p", function()
		Project.List()
	end, "project List")

	Map("s", function()
		Settings.Open()
	end, "Settings")

	Map("l", function()
		Project.Load_Layout()
	end, "Load layout")

	Map("L", function()
		Project.Save_Layout()
	end, "Save current project as layout")

	Map("o", function()
		Project.Open_Last()
	end, "Open last project")

	Map("c", function()
		vim.cmd("HyperMaxConfig")
	end, "Show configuration")

	Map("r", function()
		vim.cmd("HyperMaxCreate")
	end, "Create project using wizard")

	Map("n", function()
		Project.Create(Config.options)
	end, "New Project")

	Map("h", function()
		vim.cmd("HyperMaxHealthCheck")
	end, "Health Check")
end

return Keymaps
