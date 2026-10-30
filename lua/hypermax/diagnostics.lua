-- Project-scoped diagnostics collection and quickfix integration.
local Diagnostics = {}

local function Normalize(path)
	local absolute = vim.fn.fnamemodify(path, ":p"):gsub("\\", "/")
	if absolute ~= "/" then absolute = absolute:gsub("/+$", "") end
	return absolute
end

local function Is_Within(root, path)
	if path == root then return true end
	if root == "/" then return path:sub(1, 1) == "/" end
	return path:sub(1, #root + 1) == root .. "/"
end

local function Resolve_Root(root)
	if type(root) ~= "string" or root == "" then
		local name = vim.api.nvim_buf_get_name(0)
		root = name ~= "" and name or vim.fn.getcwd()
	end
	root = Normalize(root)
	-- Buffers may be named before their file is written. Treat any non-directory
	-- path as a file path and search upward from its parent.
	if vim.fn.isdirectory(root) ~= 1 then root = Normalize(vim.fn.fnamemodify(root, ":h")) end

	local current = root
	while current and current ~= "" do
		if vim.fn.isdirectory(current .. "/.hmc") == 1 then return current end
		local parent = vim.fn.fnamemodify(current, ":h")
		if parent == current then break end
		current = parent
	end
	return root
end

function Diagnostics.Collect(root, options)
	options = options or {}
	root = Resolve_Root(root)
	local result = { root = root, items = {}, errors = 0, warnings = 0, info = 0, hints = 0, total = 0 }
	if type(vim.diagnostic.get) ~= "function" then return result end

	local severity = vim.diagnostic.severity or {}
	local buffers = options.buffers or vim.api.nvim_list_bufs()
	for _, bufnr in ipairs(buffers) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			local filename = vim.api.nvim_buf_get_name(bufnr)
			if filename ~= "" then
				filename = Normalize(filename)
				if Is_Within(root, filename) then
					for _, diagnostic in ipairs(vim.diagnostic.get(bufnr)) do
						local level = diagnostic.severity or severity.INFO
						local kind
						if level == severity.ERROR then kind = "E"
						elseif level == severity.WARN then kind = "W"
						elseif level == severity.HINT then kind = "H"
						else kind = "I" end

						if kind == "E" then result.errors = result.errors + 1
						elseif kind == "W" then result.warnings = result.warnings + 1
						elseif kind == "H" then result.hints = result.hints + 1
						else result.info = result.info + 1 end

						result.items[#result.items + 1] = {
							filename = filename,
							lnum = math.max(1, (tonumber(diagnostic.lnum) or 0) + 1),
							col = math.max(1, (tonumber(diagnostic.col) or 0) + 1),
							text = tostring(diagnostic.message or "Diagnostic"),
							type = kind == "H" and "I" or kind,
							end_lnum = diagnostic.end_lnum and diagnostic.end_lnum + 1 or nil,
							end_col = diagnostic.end_col and diagnostic.end_col + 1 or nil,
						}
					end
				end
			end
		end
	end

	table.sort(result.items, function(a, b)
		if a.filename ~= b.filename then return a.filename < b.filename end
		if a.lnum ~= b.lnum then return a.lnum < b.lnum end
		if a.col ~= b.col then return a.col < b.col end
		return a.text < b.text
	end)

	result.total = #result.items
	return result
end

function Diagnostics.Open(root, options)
	local result = Diagnostics.Collect(root, options)
	-- Replace the prior list even when the project currently has no diagnostics;
	-- otherwise users can mistake another project's stale quickfix entries.
	vim.fn.setqflist({}, " ", {
		title = "HyperMax project diagnostics",
		items = result.items,
	})
	if result.total == 0 then
		vim.notify("HyperMax: No diagnostics are currently reported for this project", vim.log.levels.INFO)
		return true, result
	end

	vim.cmd("copen")
	return true, result
end

return Diagnostics
