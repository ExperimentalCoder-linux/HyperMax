-- Displays pinned workspace tasks in the editor winbar.
-- A winbar stays visible while the user scrolls, unlike a virtual line anchored
-- to the first line of a buffer. Existing literal winbars are preserved.
local Overlay = {}

local attached = {}

local function Normalize(path)
	if type(path) ~= "string" or path == "" then return nil end
	return vim.fn.fnamemodify(vim.fn.expand(path), ":p"):gsub("\\", "/"):gsub("/+$", "")
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
	return Find_Project_Root(name)
end

local function Escape_Statusline(value)
	return tostring(value or ""):gsub("%%", "%%%%"):gsub("[%c]", " ")
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

local function Format_Tasks(tasks, width)
	local titles = {}
	for _, task in ipairs(tasks) do
		local status = (task.status or "todo"):upper()
		titles[#titles + 1] = string.format("[%s] %s", status, task.title or "Untitled task")
	end
	local label = "◆ PINNED  " .. table.concat(titles, "  •  ")
	label = Escape_Statusline(label)
	local max_width = math.max(12, (tonumber(width) or vim.o.columns) - 8)
	if vim.fn.strdisplaywidth(label) > max_width then
		local plain = label:gsub("%%%%", "%%")
		local truncated = vim.fn.strcharpart(plain, 0, math.max(8, max_width - 1)) .. "…"
		label = Escape_Statusline(truncated)
	end
	return label
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
	if original:match("^%%!") then
		attached[window] = nil
		return
	end

	local label = Format_Tasks(tasks, vim.api.nvim_win_get_width(window))
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
			if Buffer_Root(buffer) == root then
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
