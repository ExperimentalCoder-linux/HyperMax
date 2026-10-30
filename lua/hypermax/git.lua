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

-- =========================================================
-- BRANCHES, REMOTES, TAGS AND STASHES
-- =========================================================

local function Split_Lines(output)
	local items = {}
	for _, line in ipairs(output or {}) do
		line = vim.trim(line)
		if line ~= "" then items[#items + 1] = line end
	end
	return items
end

function Git.Branches(root, include_remote)
	local args = { "branch", "--format=%(refname:short)" }
	if include_remote then args = { "branch", "--all", "--format=%(refname:short)" } end
	local output, err = Git.Run(root, args)
	if not output then return nil, err end
	return Split_Lines(output)
end

function Git.Remotes(root)
	local output, err = Git.Run(root, { "remote" })
	if not output then return nil, err end
	return Split_Lines(output)
end

function Git.Remote_Details(root)
	local output, err = Git.Run(root, { "remote", "-v" })
	if not output then return nil, err end
	return Split_Lines(output)
end

function Git.Tags(root)
	local output, err = Git.Run(root, { "tag", "--list" })
	if not output then return nil, err end
	return Split_Lines(output)
end

function Git.Stashes(root)
	local output, err = Git.Run(root, { "stash", "list", "--format=%gd%x09%gs" })
	if not output then return nil, err end
	return Split_Lines(output)
end

function Git.Log(root, count)
	count = tonumber(count) or 10
	if count ~= count or count == math.huge or count == -math.huge then count = 10 end
	count = math.max(1, math.min(100, math.floor(count)))
	return Git.Run(root, { "--no-pager", "log", "-" .. tostring(count), "--format=%h%x09%s%x09%an%x09%ar" })
end

function Git.Diff(root, staged)
	local args = { "--no-pager", "diff", "--stat" }
	if staged then args[#args + 1] = "--cached" end
	return Git.Run(root, args)
end

function Git.Diff_Name_Status(root, staged)
	local args = { "--no-pager", "diff", "--name-status" }
	if staged then args[#args + 1] = "--cached" end
	return Git.Run(root, args)
end

-- =========================================================
-- COMMON MUTATIONS
-- =========================================================

local function Is_Safe_Relative_Path(path)
	if type(path) ~= "string" or path == "" or path:find("[%c]") or path:find("\\") then return false end
	if path:sub(1, 1) == "/" or path:match("^%a:") then return false end
	for part in path:gmatch("[^/]+") do
		if part == "." or part == ".." then return false end
	end
	return true
end

function Git.Stage(root, relative_path)
	if not Is_Safe_Relative_Path(relative_path) then return nil, "A safe project-relative path is required" end
	return Git.Run(root, { "add", "--", relative_path })
end

function Git.Unstage(root, relative_path)
	if not Is_Safe_Relative_Path(relative_path) then return nil, "A safe project-relative path is required" end
	-- git restore --staged needs HEAD. On an unborn repository, remove the
	-- staged entry from the index without touching the working-tree file.
	local head = Git.Run(root, { "rev-parse", "--verify", "HEAD" })
	if not head then return Git.Run(root, { "rm", "--cached", "--", relative_path }) end
	return Git.Run(root, { "restore", "--staged", "--", relative_path })
end

function Git.Fetch(root, remote)
	local args = { "fetch", "--all", "--prune" }
	if type(remote) == "string" and remote ~= "" then args = { "fetch", remote, "--prune" } end
	return Git.Run(root, args)
end

function Git.Push(root, remote, branch)
	local args = { "push" }
	if type(remote) == "string" and remote ~= "" then args[#args + 1] = remote end
	if type(branch) == "string" and branch ~= "" then args[#args + 1] = branch end
	return Git.Run(root, args)
end

function Git.Pull(root, remote, branch)
	local args = { "pull" }
	if type(remote) == "string" and remote ~= "" then args[#args + 1] = remote end
	if type(branch) == "string" and branch ~= "" then args[#args + 1] = branch end
	return Git.Run(root, args)
end

local function Validate_Branch_Name(root, branch)
	if type(branch) ~= "string" or branch == "" or branch:sub(1, 1) == "-" or branch:find("[%c]") then
		return false, "Invalid branch name"
	end
	-- Let Git validate its complete ref-name grammar instead of imposing a
	-- narrower ASCII-only whitelist. The value is still a single argv item.
	local checked = Git.Run(root, { "check-ref-format", "refs/heads/" .. branch })
	if not checked then return false, "Invalid branch name" end
	return true
end

function Git.Switch_Branch(root, branch)
	local valid, err = Validate_Branch_Name(root, branch)
	if not valid then return nil, err end
	return Git.Run(root, { "switch", branch })
end

function Git.Create_Branch(root, branch)
	local valid, err = Validate_Branch_Name(root, branch)
	if not valid then return nil, err end
	return Git.Run(root, { "switch", "-c", branch })
end

function Git.Delete_Branch(root, branch, force)
	local valid, err = Validate_Branch_Name(root, branch)
	if not valid then return nil, err end
	return Git.Run(root, { "branch", force and "-D" or "-d", branch })
end

local function Validate_Tag(root, tag)
	if type(tag) ~= "string" or tag == "" or tag:sub(1, 1) == "-" or tag:find("[%c%s]") then
		return false, "Invalid tag name"
	end
	local checked, err = Git.Run(root, { "check-ref-format", "refs/tags/" .. tag })
	if not checked then return false, err or "Invalid tag name" end
	return true
end

function Git.Create_Tag(root, tag, message)
	local valid, err = Validate_Tag(root, tag)
	if not valid then return nil, err end
	if type(message) == "string" and vim.trim(message) ~= "" then
		return Git.Run(root, { "tag", "-a", tag, "-m", message })
	end
	return Git.Run(root, { "tag", tag })
end

function Git.Delete_Tag(root, tag)
	local valid, err = Validate_Tag(root, tag)
	if not valid then return nil, err end
	return Git.Run(root, { "tag", "-d", tag })
end

function Git.Stash(root, message)
	local args = { "stash", "push", "--include-untracked" }
	if type(message) == "string" and vim.trim(message) ~= "" then
		args[#args + 1] = "-m"
		args[#args + 1] = message
	end
	return Git.Run(root, args)
end

local function Is_Safe_Stash_Reference(reference)
	return type(reference) == "string" and (reference == "refs/stash" or reference:match("^stash@{%d+}$") ~= nil)
end

function Git.Stash_Pop(root, reference)
	local args = { "stash", "pop" }
	if reference ~= nil and reference ~= "" then
		if not Is_Safe_Stash_Reference(reference) then return nil, "Invalid stash reference" end
		args[#args + 1] = reference
	end
	return Git.Run(root, args)
end

function Git.Stash_Apply(root, reference)
	local args = { "stash", "apply" }
	if reference ~= nil and reference ~= "" then
		if not Is_Safe_Stash_Reference(reference) then return nil, "Invalid stash reference" end
		args[#args + 1] = reference
	end
	return Git.Run(root, args)
end

function Git.Add_Remote(root, name, url)
	if type(name) ~= "string" or not name:match("^[%w_.-]+$") or name:sub(1, 1) == "-" then return nil, "Invalid remote name" end
	if type(url) ~= "string" or vim.trim(url) == "" or vim.trim(url):sub(1, 1) == "-" then return nil, "A valid remote URL is required" end
	return Git.Run(root, { "remote", "add", name, vim.trim(url) })
end

function Git.Remove_Remote(root, name)
	if type(name) ~= "string" or not name:match("^[%w_.-]+$") or name:sub(1, 1) == "-" then return nil, "Invalid remote name" end
	return Git.Run(root, { "remote", "remove", name })
end

return Git
