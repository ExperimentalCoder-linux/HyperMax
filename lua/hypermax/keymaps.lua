local Settings = require("hypermax.settings")
local Layouts = require("hypermax.layouts")
local Config = require("hypermax.config")
local Project = require("hypermax.project")

local Keymaps = {}

-- =========================================================
-- HEALTH CHECK
-- =========================================================

local function Run_Health_Check()
	-- Find the plugin root from this file's location.
	local source = debug.getinfo(1, "S").source

	if source:sub(1, 1) == "@" then
		source = source:sub(2)
	end

	local plugin_root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))

	local test_file = plugin_root .. "/tests/run.lua"

	if vim.fn.filereadable(test_file) ~= 1 then
		vim.notify("HyperMax: Could not find tests/run.lua\n" .. test_file, vim.log.levels.ERROR)
		return
	end

	vim.notify("HyperMax: Running health checks...", vim.log.levels.INFO)

	-- Run tests in a clean Neovim process.
	vim.system({
		vim.v.progpath,
		"--headless",
		"-u",
		"NONE",
		"-c",
		"set rtp^=.",
		"-c",
		"luafile tests/run.lua",
		"-c",
		"qa!",
	}, {
		cwd = plugin_root,
		text = true,
	}, function(result)
		vim.schedule(function()
			local output = {
				"HyperMax Health Check",
				"=====================",
				"",
				"Exit code: " .. tostring(result.code),
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

			-- Display results in a scratch buffer.
			vim.cmd("botright new")

			local buffer = vim.api.nvim_get_current_buf()

			vim.bo[buffer].buftype = "nofile"
			vim.bo[buffer].bufhidden = "wipe"
			vim.bo[buffer].swapfile = false
			vim.bo[buffer].filetype = "text"

			vim.api.nvim_buf_set_lines(buffer, 0, -1, false, output)

			vim.bo[buffer].modifiable = false

			if result.code == 0 then
				vim.notify("HyperMax: Health checks passed", vim.log.levels.INFO)
			else
				vim.notify(
					"HyperMax: Health checks failed (exit code " .. tostring(result.code) .. ")",
					vim.log.levels.ERROR
				)
			end
		end)
	end)
end

-- =========================================================
-- KEYMAP HELPER
-- =========================================================

local function Map(key, action, description)
	vim.keymap.set("n", "<leader>+" .. key, action, {
		desc = "HyperMax: " .. description,
		silent = true,
	})
end

-- =========================================================
-- SETUP
-- =========================================================

function Keymaps.Setup(Project, Settings, Layouts)
	-- Register the health-check command.
	pcall(vim.api.nvim_del_user_command, "HyperMaxHealthCheck")

	vim.api.nvim_create_user_command("HyperMaxHealthCheck", Run_Health_Check, {
		desc = "Run HyperMax health checks",
	})

	-- =====================================================
	-- MAIN MENU
	-- =====================================================

	Map("+", function()
		vim.ui.select({
			"Projects",
			"Settings",
			"Load layout",
			"Save current project as layout",
			"Open last project",
			"List layouts",
			"Health Check",
		}, {
			prompt = "HyperMax",
		}, function(choice)
			if not choice then
				return
			end

			if choice == "Projects" then
				Project.List()
			elseif choice == "Settings" then
				Settings.Open()
			elseif choice == "Load layout" then
				Project.Load_Layout()
			elseif choice == "Save current project as layout" then
				Project.Save_Layout()
			elseif choice == "Open last project" then
				Project.Open_Last()
			elseif choice == "List layouts" then
				local ids = Layouts.Get_IDs()
				local choices = {}

				for _, id in ipairs(ids) do
					local layout = Layouts.Get(id)

					if layout then
						choices[#choices + 1] = layout
					end
				end

				if #choices == 0 then
					vim.notify("HyperMax: No layouts are available", vim.log.levels.WARN)
					return
				end

				vim.ui.select(choices, {
					prompt = "Choose layout",
					format_item = function(layout)
						local name = layout.name or layout.id

						if layout.description and layout.description ~= "" then
							return name .. " — " .. layout.description
						end

						return name
					end,
				}, function(layout)
					if not layout then
						return
					end

					Project.Create(
						vim.tbl_deep_extend(
							"force",
							{},
							require("hypermax.config").options or {},
							{ default_layout = layout.id }
						)
					)
				end)
			elseif choice == "Health Check" then
				Run_Health_Check()
			end
		end)
	end, "Open menu")

	-- =====================================================
	-- PROJECTS
	-- =====================================================

	Map("p", function()
		Project.List()
	end, "List projects")

	Map("n", function()
		Project.Create(require("hypermax.config").options)
	end, "New project")

	Map("r", function()
		vim.cmd("HyperMaxCreate")
	end, "Create project using wizard")

	Map("o", function()
		Project.Open_Last()
	end, "Open last project")

	Map("q", function()
		Project.Quick_Create()
	end, "Quick project creation")

	-- =====================================================
	-- SETTINGS AND LAYOUTS
	-- =====================================================

	Map("s", function()
		Settings.Open()
	end, "Settings")

	Map("l", function()
		Project.Load_Layout()
	end, "Load layout")

	Map("L", function()
		Project.Save_Layout()
	end, "Save current project as layout")

	Map("c", function()
		vim.cmd("HyperMaxConfig")
	end, "Show configuration")

	-- =====================================================
	-- HEALTH CHECK
	-- =====================================================

	Map("h", function()
		Run_Health_Check()
	end, "Health check")
end

return Keymaps
