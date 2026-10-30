-- Local workspace snapshots and rollback support.
-- Brotli compression is used when its executable is available; raw snapshots
-- remain the portable fallback and can always be restored without it.
local History = {}

local uv = vim.uv or vim.loop
local State = { buffer = nil, window = nil, root = nil, items = {} }
local INDEX_VERSION = 1
local MAX_INDEX_ENTRIES = 500

local function Join(...)
	return table.concat({ ... }, "/"):gsub("/+", "/")
end

local function Normalize(path)
	if type(path) ~= "string" or path == "" then
		local buffer_name = vim.api.nvim_buf_get_name(0)
		path = buffer_name ~= "" and buffer_name or vim.fn.getcwd()
	end
	local absolute = vim.fn.fnamemodify(vim.fn.expand(path), ":p"):gsub("\\", "/")
	if absolute ~= "/" then absolute = absolute:gsub("/+$", "") end
	return absolute
end

local function Notify(message, level)
	vim.notify("HyperMax: " .. message, level or vim.log.levels.INFO)
end

local function Is_Project(root)
	local metadata = uv.fs_lstat(root .. "/.hmc")
	return metadata ~= nil and metadata.type == "directory"
end

local function Resolve_Root(path)
	path = Normalize(path)
	local stat = uv.fs_stat(path)
	if stat and stat.type == "file" then path = vim.fn.fnamemodify(path, ":h") end
	local current = path
	while current and current ~= "" do
		if Is_Project(current) then return current end
		local parent = vim.fn.fnamemodify(current, ":h")
		if parent == current then break end
		current = parent
	end
	return path
end

local function Safe_Relative(path)
	if type(path) ~= "string" or path == "" or path:find("[%c]") then return false end
	path = path:gsub("\\", "/")
	if path:sub(1, 1) == "/" or path:match("^%a:") then return false end
	if path:find("//", 1, true) or path:sub(-1) == "/" then return false end
	local first = path:match("^([^/]+)")
	if first == ".git" or path == ".hmc/history" or path:sub(1, 13) == ".hmc/history/" then return false end
	for part in path:gmatch("[^/]+") do
		if part == ".." or part == "." or part == "" or part == ".git" then return false end
	end
	return true
end

local function Valid_ID(id)
	return type(id) == "string" and id:match("^[%w%-_]+$") ~= nil
end

local function Paths(root)
	local directory = Join(root, ".hmc", "history")
	return {
		directory = directory,
		index = Join(directory, "index.json"),
		snapshots = Join(directory, "snapshots"),
	}
end

local function Ensure_Directory(path)
	path = vim.fn.fnamemodify(path, ":p")
	local existing = uv.fs_lstat(path)
	if existing then
		if existing.type == "directory" then return true end
		return false, "Path exists but is not a real directory: " .. path
	end

	local parent = vim.fn.fnamemodify(path, ":h")
	if parent ~= path then
		local parent_ok, parent_error = Ensure_Directory(parent)
		if not parent_ok then return false, parent_error end
	end

	local result = vim.fn.mkdir(path)
	local created = uv.fs_lstat(path)
	if result == 0 and (not created or created.type ~= "directory") then
		return false, "Could not create directory: " .. path
	end
	if created and created.type ~= "directory" then
		return false, "Created path is not a real directory: " .. path
	end
	return true
end

local function Read_File(path)
	local file, open_error = io.open(path, "rb")
	if not file then return nil, open_error end
	local content, read_error = file:read("*a")
	local closed, close_error = file:close()
	if content == nil then return nil, read_error or close_error end
	if closed == nil then return nil, close_error end
	return content
end

local function Write_File(path, content)
	local existing = uv.fs_lstat(path)
	if existing and existing.type == "link" then
		return false, "Refusing to write through a symbolic link: " .. path
	end
	local parent = vim.fn.fnamemodify(path, ":h")
	local ok, err = Ensure_Directory(parent)
	if not ok then return false, err end
	local file, open_error = io.open(path, "wb")
	if not file then return false, open_error end
	local wrote, write_error = file:write(content)
	local closed, close_error = file:close()
	if not wrote or closed == nil then
		return false, write_error or close_error or "Could not close file"
	end
	return true
end

local function Read_Index(root)
	local paths = Paths(root)
	local history_stat = uv.fs_lstat(paths.directory)
	if history_stat and history_stat.type ~= "directory" then return nil, "History storage is not a real directory: " .. paths.directory end
	local path = paths.index
	local index_stat = uv.fs_lstat(path)
	if index_stat and index_stat.type ~= "file" then return nil, "History index is not a regular file: " .. path end
	local content, read_error = Read_File(path)
	if index_stat and content == nil then
		return nil, "Could not read history index " .. path .. ": " .. tostring(read_error)
	end
	if not index_stat then return { version = INDEX_VERSION, snapshots = {} } end
	if content == "" then return nil, "History index is empty: " .. path end
	local ok, decoded = pcall(vim.json.decode, content)
	if not ok or type(decoded) ~= "table" then
		return nil, "History index is invalid JSON: " .. path
	end
	local snapshots = {}
	for _, item in ipairs(type(decoded.snapshots) == "table" and decoded.snapshots or {}) do
		if type(item) == "table" and type(item.id) == "string" and item.id:match("^[%w%-_]+$") then
			snapshots[#snapshots + 1] = {
				id = item.id,
				kind = item.kind == "soft" and "soft" or "hard",
				label = type(item.label) == "string" and item.label:sub(1, 200) or "Save point",
				created_at = tonumber(item.created_at) or 0,
				files = math.max(0, tonumber(item.files) or 0),
				directories = math.max(0, tonumber(item.directories) or 0),
				bytes = math.max(0, tonumber(item.bytes) or 0),
				skipped = math.max(0, tonumber(item.skipped) or 0),
				compression = item.compression == "brotli" and "brotli" or "none",
				signature = type(item.signature) == "string" and item.signature or "",
			}
		end
	end
	return { version = INDEX_VERSION, snapshots = snapshots }
end

local function Write_Index(root, index)
	local path = Paths(root).index
	local ok, encoded = pcall(vim.json.encode, {
		version = INDEX_VERSION,
		snapshots = index.snapshots or {},
	})
	if not ok then return false, encoded end
	local temporary = path .. ".tmp"
	local wrote, write_error = Write_File(temporary, encoded .. "\n")
	if not wrote then return false, write_error end
	local renamed, rename_error = uv.fs_rename(temporary, path)
	if not renamed then
		pcall(os.remove, temporary)
		return false, rename_error
	end
	return true
end

local function Copy_File(source, destination)
	local source_stat = uv.fs_lstat(source)
	if not source_stat or source_stat.type ~= "file" then
		return false, "Refusing to copy a missing, symlinked or non-regular file: " .. source
	end
	local parent_ok, parent_error = Ensure_Directory(vim.fn.fnamemodify(destination, ":h"))
	if not parent_ok then return false, parent_error end
	local copied, copy_error
	if type(uv.fs_copyfile) == "function" then
		copied, copy_error = uv.fs_copyfile(source, destination)
	end
	if not copied then
		local input, input_error = io.open(source, "rb")
		if not input then return false, "Could not read " .. source .. ": " .. tostring(input_error) end
		local output, output_error = io.open(destination, "wb")
		if not output then input:close(); return false, "Could not write " .. destination .. ": " .. tostring(output_error) end
		while true do
			local chunk = input:read(1024 * 1024)
			if not chunk then break end
			local wrote, write_error = output:write(chunk)
			if not wrote then
				input:close(); output:close(); pcall(os.remove, destination)
				return false, "Could not copy " .. source .. ": " .. tostring(write_error)
			end
		end
		input:close()
		local closed, close_error = output:close()
		if closed == nil then return false, "Could not finish copying " .. source .. ": " .. tostring(close_error) end
	end
	if source_stat.mode then pcall(uv.fs_chmod, destination, source_stat.mode % 512) end
	return true, source_stat.size or 0
end

local function Make_ID()
	local seed = tostring(os.time()) .. ":" .. tostring(uv.hrtime and uv.hrtime() or math.floor(os.clock() * 1000000000))
	return os.date("%Y%m%d-%H%M%S") .. "-" .. vim.fn.sha256(seed):sub(1, 8)
end

local function Capture(root, destination)
	local files, directories, symlinks, skipped, modes = {}, {}, {}, {}, {}
	local signature_parts = {}
	local bytes = 0
	local reserved = { [".git"] = true }

	local function Scan(directory, relative)
		local handle, scan_error = uv.fs_scandir(directory)
		if not handle then
			skipped[#skipped + 1] = { path = relative, reason = tostring(scan_error or "Could not scan directory") }
			return
		end

		while true do
			local name = uv.fs_scandir_next(handle)
			if not name then break end
			if not (relative == "" and reserved[name]) then
				local child_relative = relative == "" and name or (relative .. "/" .. name)
				-- Project metadata is part of a workspace save, but history itself
				-- must never be copied into another snapshot.
				if Safe_Relative(child_relative) then
					local source = Join(directory, name)
					local destination_path = Join(destination, child_relative)
					local stat = uv.fs_lstat(source)
					if stat and stat.type == "directory" then
						local made, make_error = Ensure_Directory(destination_path)
						if made then
							directories[#directories + 1] = child_relative
							modes[child_relative] = stat.mode and (stat.mode % 512) or nil
							Scan(source, child_relative)
						else
							skipped[#skipped + 1] = { path = child_relative, reason = tostring(make_error) }
						end
					elseif stat and stat.type == "file" then
						local copied, size_or_error = Copy_File(source, destination_path)
						if copied then
							files[#files + 1] = child_relative
							modes[child_relative] = stat.mode and (stat.mode % 512) or nil
							bytes = bytes + size_or_error
							local modified = stat.mtime and (tostring(stat.mtime.sec or 0) .. "." .. tostring(stat.mtime.nsec or 0)) or "0"
							signature_parts[#signature_parts + 1] = child_relative .. ":" .. tostring(stat.size or 0) .. ":" .. modified
						else
							skipped[#skipped + 1] = { path = child_relative, reason = tostring(size_or_error) }
						end
					elseif stat and stat.type == "link" and type(uv.fs_readlink) == "function" then
						local target, link_error = uv.fs_readlink(source)
						if type(target) == "string" then
							local target_stat = uv.fs_stat(source)
							symlinks[#symlinks + 1] = {
								path = child_relative,
								target = target,
								type = target_stat and target_stat.type == "directory" and "directory" or "file",
							}
						else
							skipped[#skipped + 1] = { path = child_relative, reason = tostring(link_error or "Could not read symbolic link") }
						end
					else
						-- Sockets, devices and FIFOs are not serialized as file data.
						skipped[#skipped + 1] = { path = child_relative, reason = "Unsupported filesystem entry" }
					end
				end
			end
		end
	end

	Scan(root, "")
	table.sort(files)
	table.sort(directories)
	table.sort(symlinks, function(a, b) return a.path < b.path end)
	table.sort(signature_parts)
	table.sort(skipped, function(a, b) return a.path < b.path end)
	return {
		version = 1,
		files = files,
		directories = directories,
		symlinks = symlinks,
		modes = modes,
		skipped = skipped,
		bytes = bytes,
		signature = vim.fn.sha256(table.concat(signature_parts, "\n")),
		captured_at = os.time(),
	}
end

local function Run_Brotli(arguments)
	if vim.fn.executable("brotli") ~= 1 or type(vim.system) ~= "function" then
		return nil, "Brotli is not available"
	end
	local ok, process = pcall(vim.system, arguments, { text = false })
	if not ok or not process or type(process.wait) ~= "function" then
		return nil, tostring(process or "Could not start Brotli")
	end
	local waited, result = pcall(process.wait, process)
	if not waited then return nil, tostring(result) end
	if type(result) ~= "table" or result.code ~= 0 then
		local detail = type(result) == "table" and (result.stderr or result.stdout) or nil
		return nil, tostring(detail or "Brotli returned a non-zero exit code")
	end
	return true
end

local function Compress_Snapshot(manifest, directory)
	if #manifest.files == 0 or vim.fn.executable("brotli") ~= 1 or type(vim.system) ~= "function" then
		manifest.compression = "none"
		return
	end

	-- Store compressed data in a sibling tree, not beside each raw file. A
	-- project may legitimately contain both "asset" and "asset.br"; appending
	-- .br in-place would overwrite one of those captured files.
	local snapshot_directory = vim.fn.fnamemodify(directory, ":h")
	local compressed_directory = Join(snapshot_directory, "compressed")
	for _, relative in ipairs(manifest.files) do
		local source = Join(directory, relative)
		local destination = Join(compressed_directory, relative)
		local parent_ok = Ensure_Directory(vim.fn.fnamemodify(destination, ":h"))
		local ok = parent_ok and Run_Brotli({ "brotli", "-q", "6", "-f", "-o", destination, source })
		local stat = uv.fs_lstat(destination)
		if not ok or not stat or stat.type ~= "file" then
			pcall(vim.fn.delete, compressed_directory, "rf")
			manifest.compression = "none"
			return
		end
	end

	-- All compressed copies are complete before raw copies are removed. A
	-- failed unlink only leaves harmless extra storage; the manifest still
	-- points at the verified compressed files.
	for _, relative in ipairs(manifest.files) do
		pcall(os.remove, Join(directory, relative))
	end
	manifest.compression = "brotli"
end

local function Is_Contained_Regular_File(directory, relative)
	if not Safe_Relative(relative) then return false end
	local current = directory
	local parts = {}
	for part in relative:gmatch("[^/]+") do parts[#parts + 1] = part end
	for index, part in ipairs(parts) do
		current = Join(current, part)
		local stat = uv.fs_lstat(current)
		if not stat or stat.type == "link" then return false end
		if index == #parts then
			if stat.type ~= "file" then return false end
		elseif stat.type ~= "directory" then
			return false
		end
	end
	return true
end

local function Restore_Compressed_File(source, destination, mode)
	local parent_ok, parent_error = Ensure_Directory(vim.fn.fnamemodify(destination, ":h"))
	if not parent_ok then return false, parent_error end
	local temporary = destination .. ".hypermax-restore-tmp"
	pcall(os.remove, temporary)
	local ok, err = Run_Brotli({ "brotli", "-d", "-f", "-o", temporary, source })
	if not ok then
		pcall(os.remove, temporary)
		return false, err
	end
	local stat = uv.fs_lstat(temporary)
	if not stat or stat.type ~= "file" then
		pcall(os.remove, temporary)
		return false, "Brotli did not produce a regular restored file"
	end
	local renamed, rename_error = uv.fs_rename(temporary, destination)
	if not renamed then
		pcall(os.remove, temporary)
		return false, rename_error
	end
	if mode then pcall(uv.fs_chmod, destination, mode) end
	return true
end

function History.Get_Snapshots(root)
	root = Resolve_Root(root)
	if not Is_Project(root) then return nil, "Open a HyperMax project before viewing its history" end
	local index, err = Read_Index(root)
	if not index then return nil, err end
	table.sort(index.snapshots, function(a, b)
		if a.created_at ~= b.created_at then return a.created_at > b.created_at end
		return a.id > b.id
	end)
	return index.snapshots
end

function History.Save(root, kind, label)
	root = Resolve_Root(root)
	if not Is_Project(root) then return false, "Open a HyperMax project before creating a save point" end
	kind = kind == "soft" and "soft" or "hard"
	label = type(label) == "string" and vim.trim(label):sub(1, 200) or ""
	if label == "" then label = kind == "soft" and "Automatic successful-run save" or "Manual save point" end

	local paths = Paths(root)
	local ok, err = Ensure_Directory(paths.snapshots)
	if not ok then return false, err end
	local index, index_error = Read_Index(root)
	if not index then return false, index_error end
	table.sort(index.snapshots, function(a, b) return a.created_at > b.created_at end)

	local id = Make_ID()
	local snapshot_directory = Join(paths.snapshots, id)
	local content_directory = Join(snapshot_directory, "files")
	ok, err = Ensure_Directory(content_directory)
	if not ok then return false, err end

	local manifest = Capture(root, content_directory)
	-- Do not deduplicate using size/mtime alone: files can change while keeping
	-- both values the same. A real soft save must never silently miss content.
	Compress_Snapshot(manifest, content_directory)

	local manifest_ok, manifest_json = pcall(vim.json.encode, manifest)
	if not manifest_ok then
		pcall(vim.fn.delete, snapshot_directory, "rf")
		return false, manifest_json
	end
	local manifest_saved, manifest_error = Write_File(Join(snapshot_directory, "manifest.json"), manifest_json .. "\n")
	if not manifest_saved then
		pcall(vim.fn.delete, snapshot_directory, "rf")
		return false, manifest_error
	end

	local item = {
		id = id,
		kind = kind,
		label = label,
		created_at = os.time(),
		files = #manifest.files,
		directories = #manifest.directories,
		bytes = manifest.bytes,
		skipped = #manifest.skipped,
		compression = manifest.compression,
		signature = manifest.signature,
	}
	index.snapshots[#index.snapshots + 1] = item
	table.sort(index.snapshots, function(a, b) return a.created_at > b.created_at end)
	local pruned = {}
	while #index.snapshots > MAX_INDEX_ENTRIES do
		local removed = table.remove(index.snapshots)
		pruned[#pruned + 1] = removed.id
	end
	local saved, save_error = Write_Index(root, index)
	if not saved then
		pcall(vim.fn.delete, snapshot_directory, "rf")
		return false, save_error
	end
	for _, removed_id in ipairs(pruned) do
		pcall(vim.fn.delete, Join(paths.snapshots, removed_id), "rf")
	end
	return true, item
end

local function Read_Manifest(root, id)
	if not Valid_ID(id) then return nil, "Invalid save point ID" end
	local paths = Paths(root)
	local history_stat = uv.fs_lstat(paths.directory)
	local snapshots_stat = uv.fs_lstat(paths.snapshots)
	if not history_stat or history_stat.type ~= "directory" or not snapshots_stat or snapshots_stat.type ~= "directory" then
		return nil, "Snapshot storage directory is missing or unsafe"
	end
	local snapshot_directory = Join(paths.snapshots, id)
	local snapshot_stat = uv.fs_lstat(snapshot_directory)
	if not snapshot_stat or snapshot_stat.type ~= "directory" then return nil, "Save point directory is missing or unsafe: " .. id end
	local content_directory = Join(snapshot_directory, "files")
	local content_stat = uv.fs_lstat(content_directory)
	if not content_stat or content_stat.type ~= "directory" then return nil, "Save point files directory is missing or unsafe: " .. id end
	if not Is_Contained_Regular_File(snapshot_directory, "manifest.json") then
		return nil, "Save point manifest is missing or unsafe: " .. id
	end
	local content, read_error = Read_File(Join(snapshot_directory, "manifest.json"))
	if not content then return nil, "Could not read save point manifest " .. id .. ": " .. tostring(read_error) end
	local ok, manifest = pcall(vim.json.decode, content)
	if not ok or type(manifest) ~= "table" or type(manifest.files) ~= "table" or type(manifest.directories) ~= "table" then
		return nil, "Save point manifest is invalid: " .. id
	end
	local compression = manifest.compression or "none"
	if compression ~= "none" and compression ~= "brotli" then
		return nil, "Save point uses an unsupported compression format: " .. tostring(compression)
	end
	if compression == "brotli" and (vim.fn.executable("brotli") ~= 1 or type(vim.system) ~= "function") then
		return nil, "This save point is Brotli-compressed; install the brotli command to restore it"
	end

	local files, directories = {}, {}
	local seen_files, seen_directories = {}, {}
	for _, relative in ipairs(manifest.files) do
		if not Safe_Relative(relative) then return nil, "Save point contains an unsafe file path" end
		if seen_files[relative] then return nil, "Save point contains a duplicate file path: " .. relative end
		seen_files[relative] = true
		local stored_path = compression == "brotli" and Join("compressed", relative) or Join("files", relative)
		if not Is_Contained_Regular_File(snapshot_directory, stored_path) then
			return nil, "Save point file is missing or unsafe: " .. relative
		end
		files[#files + 1] = relative
	end
	for _, relative in ipairs(manifest.directories) do
		if not Safe_Relative(relative) then return nil, "Save point contains an unsafe directory path" end
		if seen_directories[relative] then return nil, "Save point contains a duplicate directory path: " .. relative end
		if seen_files[relative] then return nil, "Save point path is both a file and directory: " .. relative end
		seen_directories[relative] = true
		directories[#directories + 1] = relative
	end
	local symlinks, seen_links = {}, {}
	for _, link in ipairs(type(manifest.symlinks) == "table" and manifest.symlinks or {}) do
		if type(link) ~= "table" or not Safe_Relative(link.path) or type(link.target) ~= "string" then
			return nil, "Save point contains an invalid symbolic link"
		end
		if seen_links[link.path] or seen_files[link.path] or seen_directories[link.path] then
			return nil, "Save point contains a duplicate path: " .. link.path
		end
		seen_links[link.path] = true
		symlinks[#symlinks + 1] = {
			path = link.path,
			target = link.target,
			type = link.type == "directory" and "directory" or "file",
		}
	end
	for relative in pairs(seen_links) do
		local parent = relative:match("^(.*)/[^/]+$")
		while parent do
			if seen_files[parent] or seen_links[parent] then
				return nil, "Save point link path is nested under a non-directory entry: " .. parent
			end
			parent = parent:match("^(.*)/[^/]+$")
		end
	end
	-- A file or link cannot be used as an ancestor of another snapshot path.
	local path_types = {}
	for relative in pairs(seen_files) do path_types[relative] = "file" end
	for relative in pairs(seen_directories) do
		if path_types[relative] then return nil, "Save point path has conflicting types: " .. relative end
		path_types[relative] = "directory"
	end
	for relative in pairs(seen_links) do
		if path_types[relative] then return nil, "Save point path has conflicting types: " .. relative end
		path_types[relative] = "link"
	end
	for relative in pairs(path_types) do
		local parent = relative:match("^(.*)/[^/]+$")
		while parent do
			local parent_type = path_types[parent]
			if parent_type and parent_type ~= "directory" then
				return nil, "Save point path is nested under a non-directory entry: " .. parent
			end
			parent = parent:match("^(.*)/[^/]+$")
		end
	end
	if #symlinks > 0 and type(uv.fs_symlink) ~= "function" then
		return nil, "This Neovim build cannot restore symbolic links"
	end
	if type(manifest.skipped) ~= "table" then manifest.skipped = {} end
	manifest.files = files
	manifest.directories = directories
	manifest.symlinks = symlinks
	manifest.modes = type(manifest.modes) == "table" and manifest.modes or {}
	manifest.compression = compression
	return manifest
end

-- Remove project content without touching Git metadata anywhere in the tree.
-- A nested repository can use either a .git directory or a .git worktree file,
-- so preserve the entry itself and every parent directory needed to contain it.
local function Clear_Entry(path)
	local stat = uv.fs_lstat(path)
	if not stat then return true, false end
	if stat.type ~= "directory" then
		local removed = vim.fn.delete(path, "rf")
		if removed ~= 0 and uv.fs_lstat(path) then
			return false, false, "Could not remove current project entry: " .. path
		end
		return true, false
	end

	local handle, scan_error = uv.fs_scandir(path)
	if not handle then return false, false, tostring(scan_error or "Could not scan directory: " .. path) end
	local contains_preserved = false
	while true do
		local name = uv.fs_scandir_next(handle)
		if not name then break end
		if name == ".git" then
			contains_preserved = true
		else
			local removed, child_preserved, remove_error = Clear_Entry(Join(path, name))
			if not removed then return false, false, remove_error end
			if child_preserved then contains_preserved = true end
		end
	end

	if contains_preserved then return true, true end
	local removed = vim.fn.delete(path, "d")
	if removed ~= 0 and uv.fs_lstat(path) then
		return false, false, "Could not remove empty project directory: " .. path
	end
	return true, false
end

local function Clear_Workspace(root)
	local handle, err = uv.fs_scandir(root)
	if not handle then return false, err end
	while true do
		local name = uv.fs_scandir_next(handle)
		if not name then break end
		if name ~= ".git" and name ~= ".hmc" then
			local removed, _, remove_error = Clear_Entry(Join(root, name))
			if not removed then return false, remove_error end
		end
	end
	return true
end

local function Clear_Project_Metadata(root)
	local directory = Join(root, ".hmc")
	local metadata = uv.fs_lstat(directory)
	if not metadata or metadata.type ~= "directory" then
		return false, "The project .hmc metadata directory is missing or unsafe"
	end
	local handle, err = uv.fs_scandir(directory)
	if not handle then return false, err end
	while true do
		local name = uv.fs_scandir_next(handle)
		if not name then break end
		if name ~= "history" and name ~= ".git" then
			local removed, _, remove_error = Clear_Entry(Join(directory, name))
			if not removed then return false, remove_error end
		end
	end
	return true
end

local function Saved_Mode(manifest, relative)
	local modes = type(manifest.modes) == "table" and manifest.modes or {}
	local mode = tonumber(modes[relative])
	if mode and mode >= 0 and mode <= 511 and mode % 1 == 0 then return mode end
	return nil
end

local function Restore_Manifest(root, id, manifest)
	local snapshot_files = Join(Paths(root).snapshots, id, "files")
	local cleared, clear_error = Clear_Workspace(root)
	if not cleared then return false, clear_error end
	local metadata_cleared, metadata_error = Clear_Project_Metadata(root)
	if not metadata_cleared then return false, metadata_error end

	for _, relative in ipairs(manifest.directories) do
		if not Safe_Relative(relative) then return false, "Unsafe directory path in save point" end
		local created, create_error = Ensure_Directory(Join(root, relative))
		if not created then return false, create_error end
	end
	for _, relative in ipairs(manifest.files) do
		local destination = Join(root, relative)
		local mode = Saved_Mode(manifest, relative)
		local copied, copy_error
		if manifest.compression == "brotli" then
			copied, copy_error = Restore_Compressed_File(
				Join(Paths(root).snapshots, id, "compressed", relative), destination, mode
			)
		else
			copied, copy_error = Copy_File(Join(snapshot_files, relative), destination)
			if copied and mode then pcall(uv.fs_chmod, destination, mode) end
		end
		if not copied then return false, copy_error end
	end
	for _, link in ipairs(manifest.symlinks) do
		local destination = Join(root, link.path)
		local parent_ok, parent_error = Ensure_Directory(vim.fn.fnamemodify(destination, ":h"))
		if not parent_ok then return false, parent_error end
		local flags = link.type == "directory" and { dir = true } or nil
		local linked, link_error = uv.fs_symlink(link.target, destination, flags)
		if not linked then return false, "Could not restore symbolic link " .. link.path .. ": " .. tostring(link_error) end
	end

	-- Apply directory permissions last so a restrictive parent permission
	-- cannot prevent restoring its own children.
	local directory_modes = {}
	for _, relative in ipairs(manifest.directories) do
		local mode = Saved_Mode(manifest, relative)
		if mode then directory_modes[#directory_modes + 1] = { path = relative, mode = mode } end
	end
	table.sort(directory_modes, function(a, b)
		local a_depth = select(2, a.path:gsub("/", ""))
		local b_depth = select(2, b.path:gsub("/", ""))
		if a_depth ~= b_depth then return a_depth > b_depth end
		return a.path > b.path
	end)
	for _, entry in ipairs(directory_modes) do
		pcall(uv.fs_chmod, Join(root, entry.path), entry.mode)
	end

	return true, { files = #manifest.files, symlinks = #manifest.symlinks }
end

function History.Rollback(root, id, options)
	root = Resolve_Root(root)
	if not Is_Project(root) then return false, "Open a HyperMax project before restoring a save point" end
	if not Valid_ID(id) then return false, "Invalid save point ID" end
	local index, index_error = Read_Index(root)
	if not index then return false, index_error end
	local indexed = false
	for _, item in ipairs(index.snapshots) do
		if item.id == id then indexed = true; break end
	end
	if not indexed then return false, "Save point no longer exists" end

	local manifest, manifest_error = Read_Manifest(root, id)
	if not manifest then return false, manifest_error end
	if #manifest.skipped > 0 then
		return false, string.format(
			"This save point is incomplete (%d unsupported or unreadable entries). Rollback was cancelled to prevent data loss.",
			#manifest.skipped
		)
	end

	-- Protect the current state before changing any project files.
	local safety_saved, safety_result = History.Save(root, "hard", "Automatic pre-rollback safety save")
	if not safety_saved then return false, "Could not create a safety save before rollback: " .. tostring(safety_result) end
	local safety_manifest, safety_manifest_error = Read_Manifest(root, safety_result.id)
	if not safety_manifest then
		return false, "Could not verify the safety save; rollback was cancelled: " .. tostring(safety_manifest_error)
	end
	if #safety_manifest.skipped > 0 then
		return false, string.format(
			"The current workspace has %d unsupported or unreadable entries, so it cannot be safety-saved completely. Rollback was cancelled to prevent data loss.",
			#safety_manifest.skipped
		)
	end

	local restored, restore_result = Restore_Manifest(root, id, manifest)
	if not restored then
		-- A filesystem error during restore must not leave a half-restored
		-- workspace. The safety save is already durable, so apply it directly.
		local recovery_manifest, recovery_manifest_error = Read_Manifest(root, safety_result.id)
		if recovery_manifest then
			local recovered, recovery_error = Restore_Manifest(root, safety_result.id, recovery_manifest)
			if recovered then
				return false, "Rollback failed; the original workspace was restored from safety save "
					.. safety_result.id .. ": " .. tostring(restore_result)
			end
			return false, "Rollback failed: " .. tostring(restore_result)
				.. ". Automatic recovery also failed: " .. tostring(recovery_error)
				.. ". Keep safety save " .. safety_result.id .. " for manual recovery."
		end
		return false, "Rollback failed: " .. tostring(restore_result)
			.. ". Could not read safety save: " .. tostring(recovery_manifest_error)
			.. ". Keep safety save " .. safety_result.id .. " for manual recovery."
	end

	if options and options.refresh then pcall(options.refresh, root) end
	return true, {
		id = id,
		files = restore_result.files,
		symlinks = restore_result.symlinks,
		safety_save = safety_result.id,
	}
end

function History.Delete(root, id)
	root = Resolve_Root(root)
	if not Valid_ID(id) then return false, "Invalid save point ID" end
	if not Is_Project(root) then return false, "Open a HyperMax project before deleting a save point" end
	local index, err = Read_Index(root)
	if not index then return false, err end
	local found = false
	for i = #index.snapshots, 1, -1 do
		if index.snapshots[i].id == id then table.remove(index.snapshots, i); found = true end
	end
	if not found then return false, "Save point no longer exists" end
	local saved, save_error = Write_Index(root, index)
	if not saved then return false, save_error end
	local removed = vim.fn.delete(Join(Paths(root).snapshots, id), "rf")
	if removed ~= 0 then
		return false, "Save point was removed from the index, but its storage directory could not be deleted"
	end
	return true
end

local function Close_Window()
	if State.window and vim.api.nvim_win_is_valid(State.window) then
		pcall(vim.api.nvim_win_close, State.window, true)
	end
	State.window, State.buffer = nil, nil
end

local function Selected()
	if not State.window or not vim.api.nvim_win_is_valid(State.window) then return nil end
	return State.items[vim.api.nvim_win_get_cursor(State.window)[1]]
end

local function Render()
	if not State.buffer or not vim.api.nvim_buf_is_valid(State.buffer) then return end
	local snapshots, err = History.Get_Snapshots(State.root)
	if not snapshots then Notify(tostring(err), vim.log.levels.ERROR); return end
	State.items = {}
	local lines = {
		"  HYPERMAX  /  SAVE HISTORY",
		"  Project: " .. vim.fs.basename(State.root),
		"  Enter: restore   s: hard save   d: delete   r: refresh   q: close",
		"  ─────────────────────────────────────────────────────────────────────",
	}
	if #snapshots == 0 then
		lines[#lines + 1] = "  No save points yet. Press s to create a hard save."
	else
		for _, item in ipairs(snapshots) do
			local marker = item.kind == "soft" and "SOFT" or "HARD"
			local label = string.format("  [%s] %s  %s", marker, os.date("%Y-%m-%d %H:%M:%S", item.created_at), item.label)
			lines[#lines + 1] = label
			State.items[#lines] = item
			local skipped = item.skipped > 0 and (" · " .. item.skipped .. " skipped (not restorable)") or ""
			local compression = item.compression == "brotli" and "Brotli" or "raw"
			lines[#lines + 1] = string.format("        %d files · %d folders · %.1f KiB · %s%s · %s", item.files, item.directories, item.bytes / 1024, compression, skipped, item.id)
		end
	end
	vim.bo[State.buffer].modifiable = true
	vim.api.nvim_buf_set_lines(State.buffer, 0, -1, false, lines)
	vim.bo[State.buffer].modifiable = false
	vim.bo[State.buffer].modified = false
	if State.window and vim.api.nvim_win_is_valid(State.window) then
		vim.api.nvim_win_set_cursor(State.window, { math.min(vim.api.nvim_win_get_cursor(State.window)[1], #lines), 0 })
	end
end

function History.Open(root)
	root = Resolve_Root(root)
	if not Is_Project(root) then Notify("Open a HyperMax project before viewing its history", vim.log.levels.WARN); return false end
	State.root = root
	Close_Window()
	local buffer = vim.api.nvim_create_buf(false, true)
	vim.bo[buffer].buftype = "nofile"
	vim.bo[buffer].bufhidden = "wipe"
	vim.bo[buffer].swapfile = false
	vim.bo[buffer].filetype = "hypermaxhistory"
	local Window = require("hypermax.window")
	local window = Window.Open_Float(buffer, "HyperMax Save History", math.min(100, vim.o.columns - 4), math.min(26, vim.o.lines - 4), root)
	vim.wo[window].number = false
	vim.wo[window].relativenumber = false
	vim.wo[window].signcolumn = "no"
	vim.wo[window].wrap = false
	vim.wo[window].cursorline = true
	vim.wo[window].winhl = "Normal:NormalFloat,FloatBorder:FloatBorder,CursorLine:CursorLine"
	State.buffer, State.window = buffer, window

	local function Map(key, callback, description)
		vim.keymap.set("n", key, callback, { buffer = buffer, silent = true, nowait = true, desc = description })
	end
	Map("q", Close_Window, "Close save history")
	Map("<Esc>", Close_Window, "Close save history")
	Map("r", Render, "Refresh save history")
	Map("s", function()
		local ok, result = History.Save(State.root, "hard")
		if not ok then Notify(tostring(result), vim.log.levels.ERROR) else Notify("Hard save created: " .. result.id); Render() end
	end, "Create a hard save point")
	Map("d", function()
		local item = Selected()
		if not item then Notify("Select a save point first", vim.log.levels.WARN); return end
		vim.ui.select({ "Delete", "Cancel" }, { prompt = "Delete save point '" .. item.label .. "'?" }, function(choice)
			if choice ~= "Delete" then return end
			local ok, delete_error = History.Delete(State.root, item.id)
			if not ok then Notify(tostring(delete_error), vim.log.levels.ERROR) else Render() end
		end)
	end, "Delete selected save point")
	Map("<CR>", function()
		local item = Selected()
		if not item then Notify("Select a save point first", vim.log.levels.WARN); return end
		vim.ui.select({ "Restore", "Cancel" }, {
			prompt = "Restore " .. item.label .. "? Current workspace files will be replaced. A safety save is created first.",
		}, function(choice)
			if choice ~= "Restore" then return end
			local root_now = State.root
			Close_Window()
			local ok, result = History.Rollback(root_now, item.id, {
				refresh = function(project_root)
					local Dashboard = require("hypermax.dashboard")
					if Dashboard.Get_State().root == project_root then Dashboard.Refresh() end
				end,
			})
			if not ok then Notify(tostring(result), vim.log.levels.ERROR)
			else Notify("Restored save point " .. item.id .. ". Safety save: " .. tostring(result.safety_save)) end
		end)
	end, "Restore selected save point")
	Render()
	return true
end

function History.Close()
	Close_Window()
end

function History.Get_State()
	return State
end

return History
