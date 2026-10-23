local Settings = require("hypermax.settings")
local Layouts = require("hypermax.layouts")
local Config = require("hypermax.config")

local Keymaps = {}

local function Run_Health_Check()
	-- Find this file's location.
	local source = debug.getinfo(1, "S").source

	if source:sub(1, 1) == "@" then
		source = source:sub(2)
	end

	-- Find the plugin root.
	local plugin_root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))

	local test_file = plugin_root .. "/tests/run.lua"

	if vim.fn.filereadable(test_file) ~= 1 then
		vim.notify("HyperMax: Could not find tests/run.lua\n" .. test_file, vim.log.levels.ERROR)
		return
	end

	-- Run tests in a separate, clean Neovim process.
	vim.system({
		vim.v.progpath,
		"--headless",
		"-u",
		"NONE",
		"--cmd",
		"set rtp+=" .. plugin_root,
		"-c",
		"luafile " .. test_file,
	}, {
		cwd = plugin_root,
		text = true,
	}, function(result)
		vim.schedule(function()
			local output = {
				"HyperMax Health Check",
				"====================",
				"",
				"Exit code: " .. result.code,
				"",
			}

			vim.list_extend(
				output,
				vim.split(result.stdout or "", "\n", {
					plain = true,
					trimempty = true,
				})
			)

			if result.stderr and result.stderr ~= "" then
				vim.list_extend(output, {
					"",
					"Errors:",
					result.stderr,
				})
			end

			-- Display the results in a new buffer.
			vim.cmd("botright new")
			vim.bo.buftype = "nofile"
			vim.bo.bufhidden = "wipe"
			vim.bo.swapfile = false
			vim.bo.filetype = "text"

			vim.api.nvim_buf_set_lines(0, 0, -1, false, output)

			vim.bo.modifiable = false
			vim.notify(
				"HyperMax health check finished (exit code " .. result.code .. ")",
				result.code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
			)
		end)
	end)
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
