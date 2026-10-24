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


local function Is_Protected_Relative(relative)
	for part in relative:gsub("\\", "/"):gmatch("[^/]+") do
		if part == ".hmc" or part == ".git" then return true end
	end
	return false
end

local function Relative_Path(root, full)
	local normalized_root, normalized_full = Normalize(root), Normalize(full)
	if not normalized_root or not normalized_full or not Is_Within(normalized_root, normalized_full) then return nil end
	return normalized_full:sub(#normalized_root + 2)
end

function Filesystem.Move(root, source_input, destination_input)
	if type(root) ~= "string" or root == "" then return false, nil, "Project root is not set" end
	if type(source_input) ~= "string" or vim.trim(source_input) == "" then return false, nil, "Source path is required" end
	if type(destination_input) ~= "string" or vim.trim(destination_input) == "" then return false, nil, "Destination path is required" end
	local source, source_error = Filesystem.Safe_Child(root, source_input)
	if not source then return false, nil, source_error end
	local destination, destination_error = Filesystem.Safe_Child(root, destination_input)
	if not destination then return false, nil, destination_error end
	local source_relative = Relative_Path(root, source)
	local destination_relative = Relative_Path(root, destination)
	if not source_relative or not destination_relative then return false, nil, "Paths must remain inside the project" end
	if Is_Protected_Relative(source_relative) or Is_Protected_Relative(destination_relative) then
		return false, nil, "Git and HyperMax metadata paths cannot be moved from the dashboard"
	end
	local source_stat = uv.fs_lstat(source)
	if not source_stat then return false, nil, "Source does not exist: " .. source_input end
	if source == destination then return false, nil, "Source and destination are the same path" end
	if uv.fs_lstat(destination) then return false, nil, "Destination already exists: " .. destination_input end
	if source_stat.type == "directory" and Is_Within(source, destination) then
		return false, nil, "A folder cannot be moved into itself or one of its descendants"
	end
	local parent = Normalize(vim.fn.fnamemodify(destination, ":h"))
	local parent_stat = parent and uv.fs_stat(parent)
	if not parent_stat or parent_stat.type ~= "directory" then
		return false, nil, "Destination folder does not exist: " .. tostring(parent)
	end
	local ok, err = uv.fs_rename(source, destination)
	if not ok then return false, nil, "Move failed: " .. tostring(err) end
	return true, destination
end

function Filesystem.Delete(root, input)
	if type(root) ~= "string" or root == "" then return false, "Project root is not set" end
	if type(input) ~= "string" or vim.trim(input) == "" then return false, "Path is required" end
	local path, path_error = Filesystem.Safe_Child(root, input)
	if not path then return false, path_error end
	local relative = Relative_Path(root, path)
	if not relative then return false, "Path must be inside the project" end
	if Is_Protected_Relative(relative) then return false, "Git and HyperMax metadata cannot be deleted from the dashboard" end
	if not uv.fs_lstat(path) then return false, "Path does not exist: " .. input end
	local ok, result = pcall(vim.fn.delete, path, "rf")
	if not ok or result ~= 0 then return false, "Delete failed: " .. tostring(result) end
	return true
end

function Filesystem.Exists(root, input)
	local path = Filesystem.Safe_Child(root, input)
	return path ~= nil and uv.fs_lstat(path) ~= nil
end

return Filesystem
