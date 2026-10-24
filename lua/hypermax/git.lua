-- Small, testable Git wrapper used by the HyperMax dashboard.
local Git = {}
local uv = vim.uv or vim.loop

local function Normalize(path)
	if type(path) ~= "string" or path == "" then return nil end
	local ok, result = pcall(function()
		if vim.fs and vim.fs.normalize then return vim.fs.normalize(path) end
		return vim.fn.fnamemodify(path, ":p")
	end)
	if not ok or type(result) ~= "string" or result == "" then return nil end
	if result:sub(1, 1) ~= "/" then
		local absolute_ok, absolute = pcall(vim.fn.fnamemodify, result, ":p")
		if not absolute_ok or type(absolute) ~= "string" then return nil end
		result = absolute
	end
	if result ~= "/" then result = result:gsub("/+$", "") end
	return result
end

function Git.Run(root, args)
	if type(root) ~= "string" or root == "" then return nil, "Project root is not set" end
	if type(args) ~= "table" or #args == 0 then return nil, "Git arguments must be a non-empty list" end
	if vim.fn.executable("git") ~= 1 then return nil, "Git is not installed or not on PATH" end
	local normalized_root = Normalize(root)
	if not normalized_root then return nil, "Project root is not a valid path" end
	local command = { "git", "-C", normalized_root }
	for _, arg in ipairs(args) do
		if type(arg) ~= "string" then return nil, "Git arguments must all be strings" end
		command[#command + 1] = arg
	end
	local ok, output = pcall(vim.fn.systemlist, command)
	if not ok then return nil, tostring(output) end
	local exit_code = vim.v.shell_error
	if exit_code ~= 0 then return nil, table.concat(output or {}, "\n"), exit_code end
	return output or {}, nil, 0
end

function Git.Repository_Root(root)
	local output = Git.Run(root, { "rev-parse", "--show-toplevel" })
	if not output or not output[1] or output[1] == "" then return nil end
	return Normalize(output[1])
end

function Git.Is_Repository(root)
	return Git.Repository_Root(root) ~= nil
end

function Git.Branch(root)
	local output = Git.Run(root, { "branch", "--show-current" })
	if not output then return nil end
	if output[1] and output[1] ~= "" then return output[1] end
	local commit = Git.Run(root, { "rev-parse", "--short", "HEAD" })
	if commit and commit[1] and commit[1] ~= "" then return "detached@" .. commit[1] end
	return "unborn"
end

local function Unquote_Path(path)
	if path:sub(1, 1) ~= '"' or path:sub(-1) ~= '"' then return path end
	path = path:sub(2, -2)
	path = path:gsub("\\(%d%d%d)", function(octal)
		return string.char(tonumber(octal, 8))
	end)
	path = path:gsub('\\([\\"tnr])', function(char)
		local replacements = { ["\\"] = "\\", ['"'] = '"', t = "\t", n = "\n", r = "\r" }
		return replacements[char] or char
	end)
	return path
end

function Git.Parse_Status(lines, root)
	local statuses = {}
	root = Normalize(root)
	if not root then return statuses end
	for _, row in ipairs(lines or {}) do
		if type(row) == "string" and #row >= 3 then
			local code, path = row:sub(1, 2), row:sub(4)
			local valid_code = code ~= "##" and code:match("^[ MADRCTU?!][ MADRCTU?!]$") ~= nil
			if valid_code and path ~= "" then
				if (code:find("R", 1, true) or code:find("C", 1, true)) and path:find(" -> ", 1, true) then
					path = path:match(" -> (.+)$") or path
				end
				path = Unquote_Path(path)
				local full = Normalize(root .. "/" .. path)
				if full ~= root and full:sub(1, #root + 1) == root .. "/" then
					statuses[full] = code
				end
			end
		end
	end
	return statuses
end

function Git.Status(root)
	local output, err = Git.Run(root, { "-c", "core.quotepath=false", "status", "--porcelain=v1", "--untracked-files=all" })
	if not output then return nil, err end
	local repository_root = Git.Repository_Root(root) or Normalize(root)
	return Git.Parse_Status(output, repository_root), nil, output
end

function Git.Snapshot(root)
	local snapshot = { available = false, branch = nil, statuses = {}, repository_root = nil }
	local repository_root = Git.Repository_Root(root)
	if not repository_root then return snapshot end
	snapshot.available = true
	snapshot.repository_root = repository_root
	snapshot.branch = Git.Branch(root) or "unborn"
	snapshot.statuses = Git.Status(root) or {}
	return snapshot
end

function Git.Init(root)
	return Git.Run(root, { "init" })
end

function Git.Add_All(root)
	return Git.Run(root, { "add", "-A" })
end

function Git.Commit(root, message)
	if type(message) ~= "string" or vim.trim(message) == "" then return nil, "Commit message cannot be empty" end
	return Git.Run(root, { "commit", "-m", message })
end

function Git.Recent(root, count)
	count = tonumber(count) or 5
	if count ~= count or count == math.huge or count == -math.huge then count = 5 end
	count = math.max(1, math.min(100, math.floor(count)))
	return Git.Run(root, { "--no-pager", "log", "-" .. tostring(count), "--oneline", "--decorate" })
end

return Git
