local Progress = {}

local State = {
	buffer = nil,
	window = nil,
	title = "HyperMax",
	total = 0,
	completed = 0,
	message = "Preparing...",
	output = {},
	output_limit = 8,
}

local function Is_Valid_Window()
	return State.window and vim.api.nvim_win_is_valid(State.window)
end

local function Render()
	if not State.buffer or not vim.api.nvim_buf_is_valid(State.buffer) then
		return
	end

	local width = 32
	local percent = State.total > 0 and math.floor(State.completed / State.total * 100) or 0

	percent = math.max(0, math.min(100, percent))

	local filled = math.floor(width * percent / 100)
	local bar = string.rep("█", filled) .. string.rep("░", width - filled)

	local lines = {
		" " .. State.title,
		"",
		"[" .. bar .. "]",
		string.format("%d%%  (%d/%d)", percent, State.completed, State.total),
		"",
		"Current task:",
		State.message,
		"",
		"Output:",
	}

	local start = math.max(1, #State.output - State.output_limit + 1)

	for i = start, #State.output do
		lines[#lines + 1] = State.output[i]
	end

	vim.bo[State.buffer].modifiable = true
	vim.api.nvim_buf_set_lines(State.buffer, 0, -1, false, lines)
	vim.bo[State.buffer].modifiable = false

	if Is_Valid_Window() then
		vim.api.nvim_win_set_cursor(State.window, { #lines, 0 })
	end
end

function Progress.Start(title, total)
	Progress.Close()

	State.title = title or "HyperMax"
	State.total = math.max(0, total or 0)
	State.completed = 0
	State.message = "Preparing..."
	State.output = {}

	State.buffer = vim.api.nvim_create_buf(false, true)

	vim.bo[State.buffer].buftype = "nofile"
	vim.bo[State.buffer].bufhidden = "wipe"
	vim.bo[State.buffer].swapfile = false
	vim.bo[State.buffer].modifiable = false
	vim.bo[State.buffer].filetype = "hypermax-progress"

	local width = math.min(68, vim.o.columns - 4)
	local height = math.min(18, vim.o.lines - 4)

	State.window = vim.api.nvim_open_win(State.buffer, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
		col = math.max(0, math.floor((vim.o.columns - width) / 2)),
		style = "minimal",
		border = "rounded",
		title = " HyperMax Progress ",
		title_pos = "center",
	})

	vim.wo[State.window].wrap = true
	Render()
end

function Progress.Update(message, completed, total)
	if total ~= nil then
		State.total = math.max(0, total)
	end

	if completed ~= nil then
		State.completed = math.max(0, completed)
	end

	State.message = message or State.message
	Render()
end

function Progress.Log(message)
	State.output[#State.output + 1] = tostring(message)
	Render()
end

function Progress.Increment(message)
	Progress.Update(message, math.min(State.completed + 1, State.total))
end

function Progress.Finish(success, message)
	State.message = message or (success and "Completed." or "Failed.")
	State.completed = success and State.total or State.completed

	Progress.Log(success and "Finished successfully." or "Operation failed.")
	Render()
end

function Progress.Close()
	if Is_Valid_Window() then
		vim.api.nvim_win_close(State.window, true)
	end

	if State.buffer and vim.api.nvim_buf_is_valid(State.buffer) then
		vim.api.nvim_buf_delete(State.buffer, { force = true })
	end

	State.window = nil
	State.buffer = nil
end

return Progress
