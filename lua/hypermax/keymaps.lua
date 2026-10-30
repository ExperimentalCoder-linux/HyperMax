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
				vim.list_extend(output, { "", "Errors:" })
				-- nvim_buf_set_lines accepts one line per array item. Never insert
				-- the complete stderr string as one item: it may contain newlines.
				vim.list_extend(output, vim.split(result.stderr, "\n", { plain = true, trimempty = true }))
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
-- PROJECT CONVERSION COMMANDS
-- =========================================================

local function Current_Path(argument)
	return vim.fn.fnamemodify(vim.fn.expand((argument and argument ~= "") and argument or vim.fn.getcwd()), ":p")
end

local function Confirm_Action(prompt, action)
	vim.ui.select({ "Confirm", "Cancel" }, { prompt = prompt }, function(choice)
		if choice ~= "Confirm" then return end
		local ok, result = action()
		if not ok then
			vim.notify("HyperMax: " .. tostring(result), vim.log.levels.ERROR)
		else
			vim.notify("HyperMax: " .. tostring(result or "Operation completed"), vim.log.levels.INFO)
		end
	end)
end

local function Convert_Folder(path)
	local Dashboard = require("hypermax.dashboard")
	local ok, result = Dashboard.Convert_Folder(path)
	if not ok then return false, result end
	return true, "Converted folder to HyperMax project: " .. path
end

local function Undo_Conversion(path)
	local Dashboard = require("hypermax.dashboard")
	local ok, result = Dashboard.Undo_Conversion(path)
	if not ok then return false, result end
	return true, "Conversion undone. Metadata backup: " .. tostring(result)
end

local function Scrape_Project(path)
	local Dashboard = require("hypermax.dashboard")
	local ok, result = Dashboard.Scrape(path)
	if not ok then return false, result end
	return true, "Project metadata removed. Backup: " .. tostring(result)
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
	for _, command in ipairs({ "HyperMaxConvert", "HyperMaxUndoConversion", "HyperMaxScrape" }) do
		pcall(vim.api.nvim_del_user_command, command)
	end
	vim.api.nvim_create_user_command("HyperMaxConvert", function(opts)
		local path = Current_Path(opts.args)
		local ok, result = Convert_Folder(path)
		vim.notify("HyperMax: " .. tostring(result), ok and vim.log.levels.INFO or vim.log.levels.ERROR)
	end, { nargs = "?", complete = "dir", desc = "Convert an existing folder into a HyperMax project" })
	vim.api.nvim_create_user_command("HyperMaxUndoConversion", function(opts)
		local path = Current_Path(opts.args)
		Confirm_Action("Undo folder conversion? Existing files will remain; .hmc will be backed up", function() return Undo_Conversion(path) end)
	end, { nargs = "?", complete = "dir", desc = "Undo a HyperMax folder conversion" })
	vim.api.nvim_create_user_command("HyperMaxScrape", function(opts)
		local path = Current_Path(opts.args)
		Confirm_Action("Remove HyperMax metadata from this project? A backup will be kept", function() return Scrape_Project(path) end)
	end, { nargs = "?", complete = "dir", desc = "Remove HyperMax metadata from a project" })

	-- =====================================================
	-- MAIN MENU
	-- =====================================================

	Map("+", function()
		vim.ui.select({
			"Projects",
			"Settings",
			"Load layout",
			"Save current project as layout",
			"Edit saved layout",
			"Open last project",
			"Save history / rollback",
			"Create hard save point",
			"List layouts",
			"Health Check",
			"Convert current folder into project",
			"Undo folder conversion",
			"Remove project metadata (scrape)",
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
			elseif choice == "Edit saved layout" then
				Project.Edit_Layout()
			elseif choice == "Open last project" then
				Project.Open_Last()
			elseif choice == "Save history / rollback" then
				require("hypermax.history").Open()
			elseif choice == "Create hard save point" then
				local ok, result = require("hypermax.history").Save(nil, "hard")
				vim.notify(ok and ("HyperMax: Hard save created: " .. result.id) or ("HyperMax: " .. tostring(result)),
					ok and vim.log.levels.INFO or vim.log.levels.ERROR)
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
			elseif choice == "Convert current folder into project" then
				local path = Current_Path(nil)
				local ok, result = Convert_Folder(path)
				vim.notify("HyperMax: " .. tostring(result), ok and vim.log.levels.INFO or vim.log.levels.ERROR)
			elseif choice == "Undo folder conversion" then
				local path = Current_Path(nil)
				Confirm_Action("Undo folder conversion? Existing files will remain; .hmc will be backed up", function() return Undo_Conversion(path) end)
			elseif choice == "Remove project metadata (scrape)" then
				local path = Current_Path(nil)
				Confirm_Action("Remove HyperMax metadata? A backup will be kept", function() return Scrape_Project(path) end)
			end
		end)
	end, "Open menu")

	-- =====================================================
	-- PROJECTS
	-- =====================================================

	Map("p", function()
		Project.List()
	end, "List projects")

	-- Neovim's <D-...> notation is the Super/Command modifier on terminals
	-- and GUIs that forward it. Keep the leader mappings for portability.
	vim.keymap.set("n", "<D-p>", function()
		Project.List()
	end, { desc = "HyperMax: choose a registered project", silent = true })
	vim.keymap.set("n", "<D-o>", function()
		Project.Open_Last()
	end, { desc = "HyperMax: open the last registered project", silent = true })

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

	Map("H", function()
		require("hypermax.history").Open()
	end, "Browse save history and rollbacks")

	Map("S", function()
		local ok, result = require("hypermax.history").Save(nil, "hard")
		vim.notify(ok and ("HyperMax: Hard save created: " .. result.id) or ("HyperMax: " .. tostring(result)),
			ok and vim.log.levels.INFO or vim.log.levels.ERROR)
	end, "Create a hard save point")

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
	-- WORKSPACE EXPERIENCE
	-- =====================================================

	Map("m", function()
		require("hypermax.workspace").Open()
	end, "Open HyperMax workspace")

	Map("t", function()
		require("hypermax.flow").Open_Tasks()
	end, "Open project task board")

	Map("w", function()
		require("hypermax.flow").Open_Runners()
	end, "Open project run configurations")

	Map("f", function()
		require("hypermax.workspace").Find_Files()
	end, "Find files in project")

	Map("/", function()
		require("hypermax.workspace").Search_Text()
	end, "Search text in project")

	Map("x", function()
		require("hypermax.workspace").Diagnostics()
	end, "Review current project diagnostics")

	vim.keymap.set("n", "<leader>+<Space>", function()
		require("hypermax.workspace").Palette()
	end, { desc = "HyperMax: command palette", silent = true })

	-- =====================================================
	-- HEALTH CHECK
	-- =====================================================

	Map("h", function()
		Run_Health_Check()
	end, "Health check")

	Map("C", function()
		local path = Current_Path(nil)
		local ok, result = Convert_Folder(path)
		vim.notify("HyperMax: " .. tostring(result), ok and vim.log.levels.INFO or vim.log.levels.ERROR)
	end, "Convert current folder into project")
	Map("u", function()
		local path = Current_Path(nil)
		Confirm_Action("Undo folder conversion? Existing files will remain; .hmc will be backed up", function() return Undo_Conversion(path) end)
	end, "Undo folder conversion")
	Map("X", function()
		local path = Current_Path(nil)
		Confirm_Action("Remove HyperMax metadata? A backup will be kept", function() return Scrape_Project(path) end)
	end, "Scrape project metadata")
end

Keymaps.Run_Health_Check = Run_Health_Check

return Keymaps
