-- Regression tests for project snapshots, metadata preservation and rollback.
local Test = require("tests.testlib")
local Config = require("hypermax.project_config")
local History = require("hypermax.history")
local uv = vim.uv or vim.loop

local original_global_path = Config.global_path
local global_root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
Config.global_path = global_root .. "/hypermax/config.json"

local function Root()
	local root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
	vim.fn.mkdir(root .. "/src", "p")
	local ok, err = Config.Create(root, { name = "HistoryTest", language = "lua", manager = "native" })
	assert(ok, tostring(err))
	return root
end

local function Write(path, content)
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	local file, err = io.open(path, "wb")
	assert(file, tostring(err))
	assert(file:write(content))
	assert(file:close())
end

local function Read(path)
	local file = io.open(path, "rb")
	if not file then return nil end
	local content = file:read("*a")
	file:close()
	return content
end

local function Cleanup(root)
	History.Close()
	if root then pcall(vim.fn.delete, root, "rf") end
end

Test.Run("History saves project files and .hmc settings without copying its own history", function()
	local root = Root()
	Write(root .. "/src/main.lua", "print('before')\n")
	Write(root .. "/.git/config", "git metadata stays outside snapshots\n")
	assert(Config.Save_Project_Settings(root, {
		context_position = "NE",
		entry_point = { file = "src/main.lua", ["function"] = "main" },
	}))
	Write(root .. "/.hmc/workspace.json", vim.json.encode({ version = 1, tasks = { { id = "one", title = "Original task" } }, runners = {} }))

	local ok, item = History.Save(root, "hard", "Before change")
	Test.True(ok, tostring(item))
	Test.Equal("hard", item.kind)
	local snapshots = assert(History.Get_Snapshots(root))
	Test.Equal(1, #snapshots)

	local snapshot_directory = root .. "/.hmc/history/snapshots/" .. item.id
	local manifest_file = assert(io.open(snapshot_directory .. "/manifest.json", "rb"))
	local manifest = vim.json.decode(manifest_file:read("*a")); manifest_file:close()
	Test.True(vim.tbl_contains(manifest.files, ".hmc/config.json"), "Project configuration belongs in workspace snapshots")
	Test.True(vim.tbl_contains(manifest.files, ".hmc/workspace.json"), "Tasks and runners belong in workspace snapshots")
	Test.False(vim.tbl_contains(manifest.files, ".hmc/history/index.json"), "Snapshots must not include their own history index")

	Cleanup(root)
end)

Test.Run("History rollback restores files and project metadata while preserving Git and history", function()
	local root = Root()
	Write(root .. "/src/main.lua", "print('before')\n")
	Write(root .. "/keep.txt", "keep me\n")
	Write(root .. "/.git/config", "git config must survive\n")
	Write(root .. "/nested/.git/config", "nested git config before snapshot\n")
	assert(Config.Save_Project_Settings(root, { context_position = "NE" }))
	Write(root .. "/.hmc/workspace.json", vim.json.encode({
		version = 1,
		tasks = { { id = "original", title = "Original task", status = "todo" } },
		runners = {},
	}))

	local saved, item = History.Save(root, "hard", "Known good state")
	Test.True(saved, tostring(item))
	Write(root .. "/src/main.lua", "print('changed')\n")
	Write(root .. "/new-file.txt", "this should disappear\n")
	Write(root .. "/nested/.git/config", "nested git config changed after snapshot\n")
	assert(Config.Save_Project_Settings(root, { context_position = "SW" }))
	Write(root .. "/.hmc/workspace.json", vim.json.encode({ version = 1, tasks = {}, runners = {} }))

	local restored, result = History.Rollback(root, item.id)
	Test.True(restored, tostring(result))
	Test.Equal("print('before')\n", Read(root .. "/src/main.lua"))
	Test.Equal("keep me\n", Read(root .. "/keep.txt"))
	Test.Nil(Read(root .. "/new-file.txt"), "Files created after the snapshot should be removed")
	Test.Equal("git config must survive\n", Read(root .. "/.git/config"), "Root Git metadata must not be replaced")
	Test.Equal("nested git config changed after snapshot\n", Read(root .. "/nested/.git/config"), "Nested Git metadata must not be deleted")
	Test.Equal("NE", assert(Config.Get_Project_Settings(root)).context_position)
	local workspace = vim.json.decode(assert(Read(root .. "/.hmc/workspace.json")))
	Test.Equal("Original task", workspace.tasks[1].title)
	Test.Not_Nil(result.safety_save, "A safety snapshot should be created before rollback")
	Test.Equal(2, #assert(History.Get_Snapshots(root)), "The requested save and pre-rollback safety save should both remain")

	Cleanup(root)
end)

Test.Run("History preserves symbolic links when the filesystem supports them", function()
	local root = Root()
	Write(root .. "/target.txt", "target\n")
	local linked, link_error = uv.fs_symlink("target.txt", root .. "/alias.txt")
	if not linked then
		Test.True(true, "Filesystem does not support symbolic links: " .. tostring(link_error))
		Cleanup(root)
		return
	end

	local saved, item = History.Save(root, "hard", "With symbolic link")
	Test.True(saved, tostring(item))
	uv.fs_unlink(root .. "/alias.txt")
	assert(uv.fs_symlink("missing-target", root .. "/alias.txt"))
	local restored, result = History.Rollback(root, item.id)
	Test.True(restored, tostring(result))
	Test.Equal("target.txt", uv.fs_readlink(root .. "/alias.txt"))
	Cleanup(root)
end)

Test.Run("History restores file and directory permissions", function()
	local root = Root()
	Write(root .. "/src/script.sh", "#!/bin/sh\necho saved\n")
	assert(uv.fs_chmod(root .. "/src/script.sh", 493)) -- 0755
	assert(uv.fs_chmod(root .. "/src", 448)) -- 0700
	local saved, item = History.Save(root, "hard", "Permission test")
	Test.True(saved, tostring(item))
	assert(uv.fs_chmod(root .. "/src/script.sh", 384)) -- 0600
	assert(uv.fs_chmod(root .. "/src", 493)) -- 0755
	local restored, result = History.Rollback(root, item.id)
	Test.True(restored, tostring(result))
	local file_stat = uv.fs_stat(root .. "/src/script.sh")
	local directory_stat = uv.fs_stat(root .. "/src")
	Test.Equal(493, file_stat.mode % 512)
	Test.Equal(448, directory_stat.mode % 512)
	Cleanup(root)
end)

Test.Run("History keeps every soft save rather than deduplicating by timestamps only", function()
	local root = Root()
	Write(root .. "/same-size.txt", "abc")
	local first_ok, first = History.Save(root, "soft", "First successful run")
	Test.True(first_ok, tostring(first))
	Write(root .. "/same-size.txt", "xyz")
	local second_ok, second = History.Save(root, "soft", "Second successful run")
	Test.True(second_ok, tostring(second))
	Test.Not_Equal(first.id, second.id)
	Test.Equal(2, #assert(History.Get_Snapshots(root)))
	Cleanup(root)
end)

Test.Run("History refuses unsafe IDs and incomplete rollbacks", function()
	local root = Root()
	local invalid, invalid_error = History.Delete(root, "../outside")
	Test.False(invalid)
	Test.True(tostring(invalid_error):find("Invalid", 1, true) ~= nil)

	local pipe_path = root .. "/unsupported.pipe"
	if type(uv.fs_mkfifo) == "function" then
		local made = uv.fs_mkfifo(pipe_path, 384)
		if made then
			local saved, item = History.Save(root, "hard", "Contains a special file")
			Test.True(saved, tostring(item))
			Test.True(item.skipped > 0, "Unsupported filesystem entries must be reported")
			local restored, restore_error = History.Rollback(root, item.id)
			Test.False(restored, "An incomplete snapshot must not destroy workspace files")
			Test.True(tostring(restore_error):find("prevent data loss", 1, true) ~= nil)
			uv.fs_unlink(pipe_path)
		end
	end
	Cleanup(root)
end)

Test.Run("History refuses rollback when the current state cannot be safety-saved completely", function()
	local root = Root()
	Write(root .. "/keep.txt", "preserve current state\n")
	local saved, item = History.Save(root, "hard", "Before special file")
	Test.True(saved, tostring(item))
	local pipe_path = root .. "/current.pipe"
	if type(uv.fs_mkfifo) ~= "function" or not uv.fs_mkfifo(pipe_path, 384) then
		Test.True(true, "FIFO creation is not supported in this environment")
		Cleanup(root)
		return
	end
	local restored, restore_error = History.Rollback(root, item.id)
	Test.False(restored)
	Test.True(tostring(restore_error):find("safety%-saved completely") ~= nil)
	Test.Equal("preserve current state\n", Read(root .. "/keep.txt"))
	Test.Not_Nil(uv.fs_lstat(pipe_path), "Rollback must leave unsupported current entries untouched")
	uv.fs_unlink(pipe_path)
	Cleanup(root)
end)

Test.Run("History deletes a selected save point and rejects an unknown ID", function()
	local root = Root()
	local saved, item = History.Save(root, "hard", "Delete test")
	Test.True(saved, tostring(item))
	local missing, missing_error = History.Delete(root, "not-a-real-save")
	Test.False(missing)
	Test.True(tostring(missing_error):find("no longer exists", 1, true) ~= nil)
	local deleted, delete_error = History.Delete(root, item.id)
	Test.True(deleted, tostring(delete_error))
	Test.Equal(0, #assert(History.Get_Snapshots(root)))
	Cleanup(root)
end)



Test.Run("History safely handles project files whose names end in .br", function()
	local root = Root()
	Write(root .. "/archive", "raw file data\n")
	Write(root .. "/archive.br", "a different project file\n")
	local saved, item = History.Save(root, "hard", "Compression filename collision test")
	Test.True(saved, tostring(item))
	if item.compression == "brotli" then
		Write(root .. "/archive", "changed raw file\n")
		Write(root .. "/archive.br", "changed companion file\n")
		local restored, result = History.Rollback(root, item.id)
		Test.True(restored, tostring(result))
		Test.Equal("raw file data\n", Read(root .. "/archive"))
		Test.Equal("a different project file\n", Read(root .. "/archive.br"))
	else
		Test.Equal("raw file data\n", Read(root .. "/.hmc/history/snapshots/" .. item.id .. "/files/archive"))
		Test.Equal("a different project file\n", Read(root .. "/.hmc/history/snapshots/" .. item.id .. "/files/archive.br"))
	end
	Cleanup(root)
end)

Test.Run("History refuses to overwrite an empty history index", function()
	local root = Root()
	local history_directory = root .. "/.hmc/history"
	vim.fn.mkdir(history_directory, "p")
	local index_path = history_directory .. "/index.json"
	local file = assert(io.open(index_path, "w")); file:write(""); file:close()
	local saved, save_error = History.Save(root, "hard", "Must not overwrite broken index")
	Test.False(saved)
	Test.True(tostring(save_error):find("empty", 1, true) ~= nil)
	Test.Equal("", Read(index_path), "The corrupt index must remain untouched")
	Cleanup(root)
end)

Config.global_path = original_global_path
pcall(vim.fn.delete, global_root, "rf")
