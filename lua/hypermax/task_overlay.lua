-- Displays pinned workspace tasks in the editor winbar.
-- A winbar stays visible while the user scrolls, unlike a virtual line anchored
-- to the first line of a buffer. Existing literal winbars are preserved.
local Overlay = {}

local attached = {}

local function Normalize(path)
	if type(path) ~= "string" or path == "" then return nil end
	local normalized = vim.fn.fnamemodify(vim.fn.expand(path), ":p"):gsub("\\", "/")
	if normalized == "/" or normalized:match("^%a:/$") then return normalized end
	return normalized:gsub("/+$", "")
end

local function Find_Project_Root(path)
	local Project_Config = require("hypermax.project_config")
	path = Normalize(path)
	if not path then return nil end
	if vim.fn.isdirectory(path) ~= 1 then path = vim.fn.fnamemodify(path, ":h") end
	while path and path ~= "" do
		if Project_Config.Exists(path) then return path end
		local parent = vim.fn.fnamemodify(path, ":h")
		if parent == path then break end
		path = parent
	end
	return nil
end

local function Buffer_Root(buffer)
	if not vim.api.nvim_buf_is_valid(buffer) or not vim.api.nvim_buf_is_loaded(buffer) then return nil end
	if vim.bo[buffer].buftype ~= "" then return nil end
	local name = vim.api.nvim_buf_get_name(buffer)
	if name == "" then name = vim.fn.getcwd() end
	local root = Find_Project_Root(name)
	return root and Normalize(root) or nil
end

local function Clean_Statusline(value)
	return tostring(value or ""):gsub("[%c]", " ")
end

local function Escape_Statusline(value)
	return Clean_Statusline(value):gsub("%%", "%%%%")
end

local function Restore_Window(window)
	local previous = attached[window]
	if not previous then return end
	if vim.api.nvim_win_is_valid(window) then
		local ok, current = pcall(function() return vim.wo[window].winbar end)
		if ok and current == previous.rendered then
			pcall(function() vim.wo[window].winbar = previous.original end)
		end
	end
	attached[window] = nil
end

local function Truncate_Display_Width(value, width)
	if width < 1 then return "" end
	if vim.fn.strdisplaywidth(value) <= width then return value end

	local result = ""
	local index = 0
	while true do
		local character = vim.fn.strcharpart(value, index, 1)
		if character == "" then break end
		local candidate = result .. character
		if vim.fn.strdisplaywidth(candidate .. "…") > width then break end
		result = candidate
		index = index + 1
	end
	return result .. "…"
end

local function Format_Tasks(tasks, width)
	local titles = {}
	for _, task in ipairs(tasks) do
		local status = (task.status or "todo"):upper()
		local title = task.title or "Untitled task"
		-- Put the task title before its status. In narrow splits the old format
		-- truncated after the word PINNED, hiding the only useful information.
		titles[#titles + 1] = string.format("%s [%s]", title, status)
	end
	local plain = Clean_Statusline("◆ " .. table.concat(titles, "  •  "))
	local max_width = math.max(8, tonumber(width) or (vim.o.columns - 8))
	return Escape_Statusline(Truncate_Display_Width(plain, max_width))
end

local function Apply_Window(window, root, tasks)
	if not vim.api.nvim_win_is_valid(window) then return end
	local buffer = vim.api.nvim_win_get_buf(window)
	if Buffer_Root(buffer) ~= root or #tasks == 0 then
		Restore_Window(window)
		return
	end

	local current_ok, current = pcall(function() return vim.wo[window].winbar end)
	if not current_ok then return end
	local previous = attached[window]
	local original = previous and previous.original or current
	if previous and current ~= previous.rendered then
		-- The user changed the winbar while HyperMax was active. Preserve the
		-- new value rather than restoring the stale one when tasks are unpinned.
		original = current
	end
	-- A custom `%!` expression owns its complete winbar; do not append to or
	-- replace it. Other literal winbars are extended and restored on cleanup.
	if original:match("^%s*%%!") then
		attached[window] = nil
		return
	end

	local window_width = vim.api.nvim_win_get_width(window)
	local original_width = original ~= "" and vim.fn.strdisplaywidth(original) or 0
	local available_width = math.max(8, window_width - original_width - 4)
	local label = Format_Tasks(tasks, available_width)
	local rendered = (original ~= "" and (original .. "  │  ") or "") .. "%#HyperMaxPinnedTask#" .. label .. "%*"
	vim.api.nvim_set_hl(0, "HyperMaxPinnedTask", { link = "DiagnosticInfo", default = true })
	local ok = pcall(function() vim.wo[window].winbar = rendered end)
	if ok then attached[window] = { original = original, rendered = rendered } end
end

function Overlay.Refresh_Window(window)
	window = window or vim.api.nvim_get_current_win()
	if not vim.api.nvim_win_is_valid(window) then return false end
	local buffer = vim.api.nvim_win_get_buf(window)
	local root = Buffer_Root(buffer)
	if not root then
		Restore_Window(window)
		return true
	end
	local Flow = require("hypermax.flow")
	local data, err = Flow.Load(root)
	if not data then
		Restore_Window(window)
		return false, err
	end
	local pinned = {}
	for _, task in ipairs(data.tasks or {}) do
		if task.pinned then pinned[#pinned + 1] = task end
	end
	Apply_Window(window, root, pinned)
	return true
end

function Overlay.Refresh_Project(root)
	root = Normalize(root)
	if not root then return false end
	local Flow = require("hypermax.flow")
	local data, err = Flow.Load(root)
	if not data then return false, err end
	local pinned = {}
	for _, task in ipairs(data.tasks or {}) do
		if task.pinned then pinned[#pinned + 1] = task end
	end
	for _, window in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(window) then
			local buffer = vim.api.nvim_win_get_buf(window)
			if Buffer_Root(buffer) == Normalize(root) then
				Apply_Window(window, root, pinned)
			elseif attached[window] then
				Restore_Window(window)
			end
		end
	end
	return true
end

function Overlay.Setup()
	local group = vim.api.nvim_create_augroup("HyperMaxPinnedTaskOverlay", { clear = true })
	local function Refresh_Current()
		vim.schedule(function()
			local ok, err = pcall(Overlay.Refresh_Window, vim.api.nvim_get_current_win())
			if not ok then vim.notify("HyperMax: Could not refresh pinned tasks: " .. tostring(err), vim.log.levels.WARN) end
		end)
	end
	for _, event in ipairs({ "BufEnter", "BufWinEnter", "WinEnter", "BufFilePost", "DirChanged" }) do
		vim.api.nvim_create_autocmd(event, { group = group, callback = Refresh_Current })
	end
	vim.api.nvim_create_autocmd("VimResized", {
		group = group,
		callback = function()
			vim.schedule(function()
				for _, window in ipairs(vim.api.nvim_list_wins()) do pcall(Overlay.Refresh_Window, window) end
			end)
		end,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(args)
			local window = tonumber(args.match)
			if window then attached[window] = nil end
		end,
	})
	for _, window in ipairs(vim.api.nvim_list_wins()) do pcall(Overlay.Refresh_Window, window) end
	return true
end

function Overlay.Clear_Window(window)
	Restore_Window(window or vim.api.nvim_get_current_win())
end


return Overlay
