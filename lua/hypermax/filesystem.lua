-- Safe project-relative filesystem operations for HyperMax.
local Filesystem = {}
local uv = vim.uv or vim.loop

local function Normalize(path)
	if type(path) ~= "string" or path == "" then return nil end
	local ok, result = pcall(function()
		if vim.fs and vim.fs.normalize then return vim.fs.normalize(path) end
		return vim.fn.fnamemodify(path, ":p")
	end)
	if not ok or type(result) ~= "string" then return nil end
	if result:sub(1, 1) ~= "/" then
		local absolute_ok, absolute = pcall(vim.fn.fnamemodify, result, ":p")
		if not absolute_ok or type(absolute) ~= "string" then return nil end
		result = absolute
	end
	if result ~= "/" then result = result:gsub("/+$", "") end
	return result
end

local function Is_Within(root, path)
	root, path = Normalize(root), Normalize(path)
	if not root or not path or path == root then return false end
	if root == "/" then return path:sub(1, 1) == "/" end
	return path:sub(1, #root + 1) == root .. "/"
end

local function Realpath(path)
	if uv.fs_realpath then
		local ok, result = pcall(uv.fs_realpath, path)
		if ok and result then return Normalize(result) end
	end
	return Normalize(path)
end

local function Has_Unsafe_Ancestor(root_path, root_real, path)
	local cursor = Normalize(vim.fn.fnamemodify(path, ":h"))
	while cursor do
		local stat = uv.fs_lstat(cursor)
		if stat then
			local real = Realpath(cursor)
			if real and real ~= root_real and not Is_Within(root_real, real) then
				return true, "Path crosses a symbolic link outside the project"
			end
			if cursor == root_path then break end
		end
		if cursor == root_path then break end
		local parent = Normalize(vim.fn.fnamemodify(cursor, ":h"))
		if not parent or parent == cursor then break end
		cursor = parent
	end
	return false
end

function Filesystem.Normalize(path)
	return Normalize(path)
end

function Filesystem.Is_Within(root, path)
	return Is_Within(root, path)
end

function Filesystem.Safe_Child(root, input)
	if type(root) ~= "string" or root == "" then return nil, "Project root is not set" end
	if type(input) ~= "string" then return nil, "Path must be text" end
	input = vim.trim(input):gsub("\\", "/")
	if input == "" then return nil, "Enter a non-empty relative path" end
	if input:find("%z") or input:find("[%c]") then return nil, "Path contains an invalid control character" end
	if input:sub(1, 1) == "/" or input:match("^%a:") or input:sub(1, 1) == "~" then
		return nil, "Enter a relative path inside the project"
	end
	for part in input:gmatch("[^/]+") do
		if part == "." or part == ".." then
			return nil, "Relative paths cannot contain . or .."
		end
	end
	local root_path = Normalize(root)
	if not root_path then return nil, "Project root is not a valid path" end
	local full_path = Normalize(root_path .. "/" .. input)
	if not full_path or not Is_Within(root_path, full_path) then
		return nil, "Path must stay inside the project"
	end
	local root_real = Realpath(root_path)
	local real_root = root_real or root_path
	local unsafe, reason = Has_Unsafe_Ancestor(root_path, real_root, full_path)
	if unsafe then return nil, reason end
	local existing = uv.fs_lstat(full_path)
	if existing and existing.type == "link" then
		local target = Realpath(full_path)
		if target and target ~= real_root and not Is_Within(real_root, target) then
			return nil, "Target symbolic link points outside the project"
		end
	end
	return full_path
end

local function Ensure_Directory(path)
	local stat = uv.fs_stat(path)
	if stat then
		if stat.type == "directory" then return true end
		return false, "A non-directory already exists in the path: " .. path
	end
	local ok, err = pcall(vim.fn.mkdir, path, "p")
	if not ok then return false, tostring(err) end
	stat = uv.fs_stat(path)
	if not stat or stat.type ~= "directory" then
		return false, "Could not create directory: " .. path
	end
	return true
end

function Filesystem.Create(root, kind, input)
	if input == nil or (type(input) == "string" and vim.trim(input) == "") then
		return false, nil, "cancelled"
	end
	if kind ~= "file" and kind ~= "folder" then
		return false, nil, "Unknown item type: " .. tostring(kind)
	end
	local path, path_error = Filesystem.Safe_Child(root, input)
	if not path then return false, nil, path_error end
	if uv.fs_lstat(path) then return false, nil, "Already exists: " .. tostring(input) end

	local root_path = Normalize(root)
	local parent = Normalize(vim.fn.fnamemodify(path, ":h"))
	if parent ~= root_path then
		local parent_ok, parent_error = Ensure_Directory(parent)
		if not parent_ok then return false, nil, parent_error end
	end

	if kind == "folder" then
		local ok, err = pcall(vim.fn.mkdir, path, "p")
		if not ok then return false, nil, "Could not create folder: " .. tostring(err) end
		local stat = uv.fs_stat(path)
		if not stat or stat.type ~= "directory" then
			return false, nil, "Could not create folder: " .. tostring(input)
		end
	else
		local fd, open_error = uv.fs_open(path, "wx", 420)
		if not fd then return false, nil, "Could not create file: " .. tostring(open_error) end
		local close_ok, close_error = uv.fs_close(fd)
		if close_ok == nil or close_ok == false then
			pcall(uv.fs_unlink, path)
			return false, nil, "Could not close new file: " .. tostring(close_error)
		end
	end
	return true, path
end

return Filesystem
