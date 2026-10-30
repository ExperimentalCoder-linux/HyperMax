-- Shared placement logic for HyperMax context windows.
local Window = {}

local function Resolve_Root(root)
	if type(root) == "string" and root ~= "" then
		return vim.fn.fnamemodify(vim.fn.expand(root), ":p"):gsub("/+$", "")
	end

	local buffer_name = vim.api.nvim_buf_get_name(0)
	local path = buffer_name ~= "" and buffer_name or vim.fn.getcwd()
	path = vim.fn.fnamemodify(path, ":p")
	if vim.fn.filereadable(path) == 1 then
		path = vim.fn.fnamemodify(path, ":h")
	end

	while path and path ~= "" do
		if vim.fn.isdirectory(path .. "/.hmc") == 1 then
			return path
		end
		local parent = vim.fn.fnamemodify(path, ":h")
		if parent == path then break end
		path = parent
	end

	return nil
end

function Window.Get_Position(root, fallback)
	local Project_Config = require("hypermax.project_config")
	local resolved = Resolve_Root(root)
	if not resolved then return fallback or "center" end

	local settings = Project_Config.Get_Project_Settings(resolved)
	local position = settings and settings.context_position or fallback or "center"
	if type(position) ~= "string" then return "center" end
	position = position:upper():gsub("[%s_%-]", "")

	local allowed = {
		N = true, S = true, E = true, W = true,
		NE = true, NW = true, SE = true, SW = true,
		NS = true, EW = true, C = true, CENTER = true,
	}

	return allowed[position] and position or "center"
end

function Window.Get_Config(width, height, root, options)
	options = options or {}
	local columns = math.max(1, vim.o.columns)
	local lines = math.max(1, vim.o.lines)
	width = math.max(1, math.min(tonumber(width) or 60, columns - 2))
	height = math.max(1, math.min(tonumber(height) or 20, lines - 2))

	local position = Window.Get_Position(root, options.position)
	local row, col
	local middle_row = math.max(0, math.floor((lines - height) / 2) - 1)
	local middle_col = math.max(0, math.floor((columns - width) / 2))
	local top = 1
	local bottom = math.max(0, lines - height - 3)
	local left = 1
	local right = math.max(0, columns - width - 2)

	if position == "N" then row, col = top, middle_col
	elseif position == "S" then row, col = bottom, middle_col
	elseif position == "E" then row, col = middle_row, right
	elseif position == "W" then row, col = middle_row, left
	elseif position == "NE" then row, col = top, right
	elseif position == "NW" then row, col = top, left
	elseif position == "SE" then row, col = bottom, right
	elseif position == "SW" then row, col = bottom, left
	else
		-- NS/EW intentionally mean the middle of the corresponding axis pair.
		row, col = middle_row, middle_col
	end

	return {
		relative = "editor",
		style = "minimal",
		border = options.border or "rounded",
		width = width,
		height = height,
		row = row,
		col = col,
		title = options.title,
		title_pos = options.title_pos or "center",
	}
end

function Window.Open_Float(buffer, title, width, height, root, options)
	options = options or {}
	local config = Window.Get_Config(width, height, root, {
		position = options.position,
		border = options.border,
		title = title and ("  " .. title .. "  ") or nil,
		title_pos = options.title_pos,
	})
	return vim.api.nvim_open_win(buffer, options.enter ~= false, config)
end

return Window
