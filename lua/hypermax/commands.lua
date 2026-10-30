-- HyperMax command interface.
-- The public command is deliberately scoped under :HyperMax. Feature modules
-- are required only by the command that invokes them.

---@class HyperMax.CommandSpec
---@field desc? string Description shown in command completion.
---@field run? fun(args: string[], opts: HyperMax.CommandOptions) Action for this command.
---@field subcommands? table<string, HyperMax.CommandSpec> Nested commands.
---@field complete? "dir" Argument completion mode.
---@field allow_args? boolean Whether positional arguments are accepted.

---@class HyperMax.CommandOptions
---@field args string Raw command arguments.
---@field fargs string[] Parsed command arguments.
---@field bang boolean Whether the command used a bang modifier.
---@field line1? integer First line in a command range, when present.
---@field line2? integer Last line in a command range, when present.
---@field range? integer Number of lines in the command range, when present.
---@field count? integer Explicit command count, when present.
---@field mods? string Command modifiers, when present.

local Commands = {}

---@type table<string, HyperMax.CommandSpec>|nil
local command_tree
---@type boolean
local command_registered = false

---@param message any
---@param level? integer
local function Notify(message, level)
	vim.notify("HyperMax: " .. tostring(message), level or vim.log.levels.INFO)
end

---@param argument? string
---@return string path
local function Current_Path(argument)
	local value = argument and argument ~= "" and argument or vim.fn.getcwd()
	return vim.fn.fnamemodify(vim.fn.expand(value), ":p")
end

---@param prompt string
---@param action fun(): boolean, string|nil
local function Confirm_Action(prompt, action)
	vim.ui.select({ "Confirm", "Cancel" }, { prompt = prompt }, function(choice)
		if choice ~= "Confirm" then
			return
		end

		local call_ok, action_ok, result = pcall(action)
		if not call_ok then
			Notify("Operation failed: " .. tostring(action_ok), vim.log.levels.ERROR)
			return
		end
		Notify(result or (action_ok and "Operation completed" or "Operation failed"),
			action_ok and vim.log.levels.INFO or vim.log.levels.ERROR)
	end)
end

---@param argument? string
local function Convert_Folder(argument)
	local path = Current_Path(argument)
	local ok, result = require("hypermax.dashboard").Convert_Folder(path)
	if ok then
		Notify("Converted folder to HyperMax project: " .. path)
	else
		Notify(result, vim.log.levels.ERROR)
	end
end

---@param argument? string
local function Undo_Conversion(argument)
	local path = Current_Path(argument)
	Confirm_Action("Undo folder conversion? Existing files remain; .hmc will be backed up", function()
		local ok, result = require("hypermax.dashboard").Undo_Conversion(path)
		if ok then
			return true, "Conversion undone. Metadata backup: " .. tostring(result)
		end
		return false, result
	end)
end

---@param argument? string
local function Scrape_Project(argument)
	local path = Current_Path(argument)
	Confirm_Action("Remove HyperMax metadata from this project? A backup will be kept", function()
		local ok, result = require("hypermax.dashboard").Scrape(path)
		if ok then
			return true, "Project metadata removed. Backup: " .. tostring(result)
		end
		return false, result
	end)
end

---@param api HyperMax
---@return table<string, HyperMax.CommandSpec>
local function Build_Tree(api)
	return {
		project = {
			desc = "Create, open, register, or convert projects",
			subcommands = {
				create = {
					desc = "Create a project with the project wizard",
					run = function() api.create_project() end,
				},
				list = {
					desc = "List registered HyperMax projects",
					run = function() api.list_projects() end,
				},
				["open-last"] = {
					desc = "Open the most recently opened project",
					run = function() api.open_last_project() end,
				},
				["quick-create"] = {
					desc = "Create a project using preferred defaults",
					run = function() api.quick_create_project() end,
				},
				convert = {
					desc = "Convert an existing directory into a HyperMax project",
					complete = "dir",
					allow_args = true,
					run = function(args) Convert_Folder(table.concat(args, " ")) end,
				},
				["undo-conversion"] = {
					desc = "Undo a folder conversion while preserving its files",
					complete = "dir",
					allow_args = true,
					run = function(args) Undo_Conversion(table.concat(args, " ")) end,
				},
				scrape = {
					desc = "Remove HyperMax metadata while keeping a backup",
					complete = "dir",
					allow_args = true,
					run = function(args) Scrape_Project(table.concat(args, " ")) end,
				},
			},
		},
		layout = {
			desc = "Create, edit, list, and apply reusable project layouts",
			subcommands = {
				save = {
					desc = "Capture the current directory as a layout draft",
					run = function() api.save_layout() end,
				},
				edit = {
					desc = "Edit a saved layout in a temporary JSON buffer",
					run = function() api.edit_layout() end,
				},
				load = {
					desc = "Choose and apply a saved layout",
					run = function() api.load_layout() end,
				},
				list = {
					desc = "Choose a saved layout for project creation",
					run = function() api.list_layouts() end,
				},
			},
		},
		workspace = {
			desc = "Open the workspace and its project tools",
			run = function() api.open_workspace() end,
			subcommands = {
				open = {
					desc = "Open the workspace home",
					run = function() api.open_workspace() end,
				},
				palette = {
					desc = "Open the command palette",
					run = function() api.open_palette() end,
				},
				tasks = {
					desc = "Open the current project's task board",
					run = function() api.open_tasks() end,
				},
				runs = {
					desc = "Manage project run configurations",
					run = function() api.open_runs() end,
				},
				diagnostics = {
					desc = "Show diagnostics scoped to the current project",
					run = function() api.open_diagnostics() end,
				},
			},
		},
		history = {
			desc = "Browse project save points and restore project states",
			run = function() api.open_history() end,
			subcommands = {
				open = {
					desc = "Browse saved states and rollbacks",
					run = function() api.open_history() end,
				},
				save = {
					desc = "Create a manual hard save point",
					run = function()
						local ok, result = api.save_point()
						if ok then
							local save_id = type(result) == "table" and result.id or result
							Notify("Hard save created: " .. tostring(save_id))
						else
							Notify(result, vim.log.levels.ERROR)
						end
					end,
				},
			},
		},
		settings = {
			desc = "Open HyperMax settings",
			run = function() api.open_settings() end,
		},
		config = {
			desc = "Print the active HyperMax configuration",
			run = function() vim.print(api.get_config()) end,
		},
		tutorial = {
			desc = "Open the Essentials and Advanced tutorials",
			run = function() api.open_tutorials() end,
		},
		health = {
			desc = "Run the standard Neovim health check",
			run = function() vim.cmd("checkhealth hypermax") end,
		},
	}
end

---@param tbl table<string, any>
---@return string[]
local function Sorted_Keys(tbl)
	local keys = vim.tbl_keys(tbl)
	table.sort(keys)
	return keys
end

---@param arg_lead string Current argument prefix.
---@param cmdline string Full command line.
---@param cursor_pos? integer Cursor byte position in the command line.
---@return string[] matches
function Commands.complete(arg_lead, cmdline, cursor_pos)
	local line = cmdline or ""
	if type(cursor_pos) == "number" and cursor_pos > 0 and cursor_pos < #line then
		line = line:sub(1, cursor_pos)
	end

	local tail = line:match("^['<,'>]*:?%s*HyperMax%s*(.*)$")
	if tail == nil then
		return {}
	end

	local has_trailing_space = tail:match("%s$") ~= nil
	local before = has_trailing_space and tail or tail:gsub("%S+$", "")
	local prefix = arg_lead or ""
	local tokens = {}
	for token in before:gmatch("%S+") do
		tokens[#tokens + 1] = token
	end

	---@type HyperMax.CommandSpec
	local node = { subcommands = command_tree or {} }
	for _, token in ipairs(tokens) do
		-- Once an argument-completion node is reached, ignore the rest of the
		-- partially typed path. This also supports quoted paths containing spaces.
		if node.complete == "dir" then
			return vim.fn.getcompletion(prefix, "dir")
		end
		if not node.subcommands or not node.subcommands[token] then
			return {}
		end
		node = node.subcommands[token]
	end

	if node.complete == "dir" then
		return vim.fn.getcompletion(prefix, "dir")
	end

	if not node.subcommands then
		return {}
	end

	local matches = {}
	for _, key in ipairs(Sorted_Keys(node.subcommands)) do
		if key:sub(1, #prefix) == prefix then
			matches[#matches + 1] = key
		end
	end
	return matches
end

---@param node HyperMax.CommandSpec
---@param path string
---@param node HyperMax.CommandSpec
---@param path string
local function Show_Usage(node, path)
	local names = Sorted_Keys(node.subcommands or {})
	local lines = {}
	for _, name in ipairs(names) do
		local child = node.subcommands[name]
		lines[#lines + 1] = string.format("  %-20s %s", name, child.desc or "")
	end
	Notify("Available commands for '" .. path .. "':\n" .. table.concat(lines, "\n"), vim.log.levels.INFO)
end

---@param tokens string[]
---@param opts HyperMax.CommandOptions
---@return boolean success
function Commands.execute(tokens, opts)
	---@type HyperMax.CommandSpec
	local node = { subcommands = command_tree or {} }
	local path = ":HyperMax"
	local index = 1

	if #tokens == 0 then
		local workspace = node.subcommands.workspace
		if workspace and workspace.run then
			local ok, err = pcall(workspace.run, {}, opts)
			if not ok then
				Notify("Command failed: " .. tostring(err), vim.log.levels.ERROR)
				return false
			end
			return true
		end
		Notify("The command interface has not been initialized", vim.log.levels.ERROR)
		return false
	end

	while index <= #tokens do
		local token = tokens[index]
		if not node.subcommands or not node.subcommands[token] then
			Notify("Unknown command '" .. token .. "'. Use :HyperMax <Tab> to see available commands.", vim.log.levels.ERROR)
			return false
		end

		node = node.subcommands[token]
		path = path .. " " .. token
		index = index + 1

		if node.subcommands and index <= #tokens then
			-- Continue resolving nested command names.
		elseif node.subcommands and index > #tokens and not node.run then
			Show_Usage(node, path)
			return true
		elseif node.run then
			local args = {}
			for arg_index = index, #tokens do
				args[#args + 1] = tokens[arg_index]
			end
			if #args > 0 and node.allow_args ~= true then
				Notify("Command '" .. path .. "' does not accept arguments.", vim.log.levels.ERROR)
				return false
			end
			local ok, err = pcall(node.run, args, opts)
			if not ok then
				Notify("Command failed: " .. tostring(err), vim.log.levels.ERROR)
				return false
			end
			return true
		else
			Show_Usage(node, path)
			return true
		end
	end

	if node.run then
		local ok, err = pcall(node.run, {}, opts)
		if not ok then
			Notify("Command failed: " .. tostring(err), vim.log.levels.ERROR)
			return false
		end
		return true
	end

	Show_Usage(node, path)
	return true
end

---@param api HyperMax Public API passed into the command tree.
---@return boolean success Whether the HyperMax command was registered.
function Commands.setup(api)
	command_tree = Build_Tree(api)
	if command_registered then
		return true
	end

	-- Do not delete an existing command with the same name: it may belong to
	-- the user or another plugin. Neovim reports a name collision, which we
	-- surface without changing the existing command.
	local ok = pcall(vim.api.nvim_create_user_command, "HyperMax", function(opts)
		Commands.execute(opts.fargs or {}, opts)
	end, {
		nargs = "*",
		desc = "HyperMax project and workspace commands",
		complete = Commands.complete,
	})

	if not ok then
		return false
	end

	command_registered = true
	return true
end

return Commands
