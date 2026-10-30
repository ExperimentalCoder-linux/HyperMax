-- Tests for compatibility, file operations, and project conversion lifecycle.
local Test = require("tests.testlib")
local FS = require("hypermax.filesystem")
local Config = require("hypermax.project_config")
local uv = vim.uv or vim.loop
local original_global_path = Config.global_path
local global_test_root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
Config.global_path = global_test_root .. "/hypermax/config.json"

local function Root()
	local root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
	vim.fn.mkdir(root, "p")
	return root
end
local function Write(path, data)
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	local file = assert(io.open(path, "wb")); file:write(data or "{}"); file:close()
end
local function Cleanup(root) pcall(vim.fn.delete, root, "rf") end

local move_cases = {
	{ "rename file", "src/a.c", "src/b.c", "file" },
	{ "move file to nested folder", "src/a.c", "assets/a.c", "file" },
	{ "move file out to root", "src/a.c", "a.c", "file" },
	{ "rename folder", "src", "source", "directory" },
	{ "move folder into existing folder", "src", "assets/src", "directory" },
}
for _, case in ipairs(move_cases) do
	Test.Run("Filesystem " .. case[1], function()
		local root = Root(); vim.fn.mkdir(root .. "/src", "p"); vim.fn.mkdir(root .. "/assets", "p")
		if case[4] == "file" then Write(root .. "/src/a.c", "x") end
		local ok, destination, err = FS.Move(root, case[2], case[3])
		Test.True(ok, tostring(err)); Test.Not_Nil(uv.fs_lstat(destination)); Test.Nil(uv.fs_lstat(root .. "/" .. case[2]))
		Cleanup(root)
	end)
end

local bad_moves = {
	{ "missing source", "missing.txt", "target.txt" },
	{ "existing destination", "a.txt", "b.txt" },
	{ "unsafe source", "../outside", "inside" },
	{ "unsafe destination", "a.txt", "../outside" },
	{ "same path", "a.txt", "a.txt" },
	{ "metadata source", ".hmc/basics.json", "basics.json" },
	{ "git source", ".git/config", "config" },
}
for _, case in ipairs(bad_moves) do
	Test.Run("Filesystem rejects move: " .. case[1], function()
		local root = Root(); Write(root .. "/a.txt", "a"); Write(root .. "/b.txt", "b"); Write(root .. "/.hmc/basics.json", "{}"); Write(root .. "/.git/config", "")
		local ok = FS.Move(root, case[2], case[3]); Test.False(ok); Cleanup(root)
	end)
end

Test.Run("Filesystem delete removes file", function()
	local root = Root(); Write(root .. "/a.txt", "a")
	local ok, err = FS.Delete(root, "a.txt"); Test.True(ok, tostring(err)); Test.Nil(uv.fs_lstat(root .. "/a.txt")); Cleanup(root)
end)
Test.Run("Filesystem delete removes folder recursively", function()
	local root = Root(); Write(root .. "/folder/nested/a.txt", "a")
	local ok, err = FS.Delete(root, "folder"); Test.True(ok, tostring(err)); Test.Nil(uv.fs_lstat(root .. "/folder")); Cleanup(root)
end)
for _, path in ipairs({ "", "../outside", ".hmc", ".git", "nested/.git/config" }) do
	Test.Run("Filesystem refuses unsafe delete: " .. path, function()
		local root = Root(); Write(root .. "/.hmc/basics.json", "{}"); Write(root .. "/.git/config", ""); Write(root .. "/nested/.git/config", "")
		local ok = FS.Delete(root, path); Test.False(ok); Cleanup(root)
	end)
end

Test.Run("Legacy basic.json metadata loads", function()
	local root = Root(); vim.fn.mkdir(root .. "/.hmc", "p")
	Write(root .. "/.hmc/basic.json", vim.json.encode({ name = "Legacy", root = root, language = "c", manager = "native", entry_file = "main.c" }))
	local loaded, err = Config.Load(root); Test.Not_Nil(loaded, tostring(err)); Test.Equal("Legacy", loaded.basics.project.name); Test.Equal("main.c", loaded.basics.project.entry_point.file); Cleanup(root)
end)
Test.Run("Legacy project.json metadata loads", function()
	local root = Root(); vim.fn.mkdir(root .. "/.hmc", "p")
	Write(root .. "/.hmc/project.json", vim.json.encode({ project = { name = "OldProject", entry_point = { file = "src/main.c" } } }))
	local loaded, err = Config.Load(root); Test.Not_Nil(loaded, tostring(err)); Test.Equal("OldProject", loaded.basics.project.name); Test.Equal("src/main.c", loaded.basics.project.entry_point.file); Cleanup(root)
end)
Test.Run("Legacy settings.json is used when config.json is absent", function()
	local root = Root(); vim.fn.mkdir(root .. "/.hmc", "p"); Write(root .. "/.hmc/basics.json", vim.json.encode({ project = { name = "Compat" } })); Write(root .. "/.hmc/settings.json", vim.json.encode({ theme = "dark" }))
	local loaded, err = Config.Load(root); Test.Not_Nil(loaded, tostring(err)); Test.Equal("dark", loaded.config.settings.theme); Cleanup(root)
end)
Test.Run("Legacy files.json layout is normalized", function()
	local root = Root(); vim.fn.mkdir(root .. "/.hmc", "p"); Write(root .. "/.hmc/basics.json", vim.json.encode({ project = { name = "Compat" } })); Write(root .. "/.hmc/files.json", vim.json.encode({ files = { { path = "main.c", type = "file" } } }))
	local loaded, err = Config.Load(root); Test.Not_Nil(loaded, tostring(err)); Test.Equal("main.c", loaded.layout.entries[1].path); Cleanup(root)
end)
Test.Run("Convert existing folder to project", function()
	local root = Root(); Write(root .. "/main.c", "int main(void){}")
	local ok, err = Config.Convert_Folder(root, { language = "c" }); Test.True(ok, tostring(err)); Test.True(Config.Exists(root))
	local loaded = assert(Config.Load(root)); Test.Equal("folder_conversion", loaded.basics.conversion.kind); Test.Equal("main.c", loaded.layout.entries[1].path); Cleanup(root)
end)
Test.Run("Conversion refuses an existing project", function()
	local root = Root(); assert(Config.Create(root, { name = "Already" })); local ok = Config.Convert_Folder(root); Test.False(ok); Cleanup(root)
end)
Test.Run("Undo conversion backs up metadata and leaves source files", function()
	local root = Root(); Write(root .. "/main.c", "source"); assert(Config.Convert_Folder(root, {}))
	local ok, backup = Config.Undo_Conversion(root); Test.True(ok, tostring(backup)); Test.False(Config.Exists(root)); Test.Not_Nil(uv.fs_stat(root .. "/main.c")); Test.Not_Nil(uv.fs_stat(backup .. "/basics.json"))
	local indexed = Config.List_Projects()
	for _, project in ipairs(indexed or {}) do Test.False(project.path == vim.fn.fnamemodify(root, ":p"), "Undone conversion should be removed from the project index") end
	Cleanup(root)
end)
Test.Run("Undo conversion refuses ordinary projects", function()
	local root = Root(); assert(Config.Create(root, { name = "manual" })); local ok = Config.Undo_Conversion(root); Test.False(ok); Test.True(Config.Exists(root)); Cleanup(root)
end)
Test.Run("Scrape removes project marker and preserves backup", function()
	local root = Root(); Write(root .. "/main.c", "source"); assert(Config.Create(root, { name = "manual" }))
	local ok, backup = Config.Scrape(root); Test.True(ok, tostring(backup)); Test.False(Config.Exists(root)); Test.Not_Nil(uv.fs_stat(root .. "/main.c")); Test.Not_Nil(uv.fs_stat(backup .. "/basics.json")); Cleanup(root)
end)
Test.Run("Scrape works with legacy metadata", function()
	local root = Root(); vim.fn.mkdir(root .. "/.hmc", "p"); Write(root .. "/.hmc/basic.json", vim.json.encode({ name = "Old" }))
	local ok, backup = Config.Scrape(root); Test.True(ok, tostring(backup)); Test.False(Config.Exists(root)); Cleanup(root)
end)


Test.Run("Converted projects register globally even outside project_dir", function()
	local root = Root()
	Write(root .. "/.gitignore", "build/\n")
	Write(root .. "/src/main.c", "int main(void) { return 0; }\n")
	local ok, err = Config.Convert_Folder(root, { language = "c" })
	Test.True(ok, tostring(err))
	local unrelated_directory = global_test_root .. "/unrelated"
	vim.fn.mkdir(unrelated_directory, "p")
	local indexed = Config.List_Projects(unrelated_directory)
	Test.Type("table", indexed)
	local expected_root = vim.fn.fnamemodify(root, ":p"):gsub("/+$", "")
	local found = false
	for _, project in ipairs(indexed) do
		if project.path == expected_root then found = true end
	end
	Test.True(found, "Converted project was not discoverable through the global index")
	Test.Equal(expected_root, Config.Get_Last_Project())
	local loaded = assert(Config.Load(root))
	Test.Equal("folder_conversion", loaded.basics.conversion.kind)
	Test.True(loaded.basics.project.id ~= nil, "Project metadata should contain a stable project ID")
	local captured_source
	for _, entry in ipairs(loaded.layout.entries) do
		if entry.path == "src/main.c" then captured_source = entry.content end
	end
	Test.Equal("int main(void) { return 0; }\n", captured_source)
	Cleanup(root)
end)

Test.Run("Project list sorts recently opened projects first", function()
	local first, second = Root(), Root()
	assert(Config.Create(first, { name = "Alpha recent test" }))
	assert(Config.Create(second, { name = "Zulu recent test" }))
	assert(Config.Mark_Project_Opened(first))
	assert(Config.Mark_Project_Opened(second))
	local projects = assert(Config.List_Projects())
	Test.Equal(vim.fn.fnamemodify(second, ":p"):gsub("/+$", ""), projects[1].path)
	Cleanup(first); Cleanup(second)
end)

Test.Run("Project capture excludes a Git worktree .git pointer file", function()
	local root = Root()
	Write(root .. "/.git", "gitdir: ../.git/worktrees/example\n")
	Write(root .. "/main.c", "int main(void) {}\n")
	assert(Config.Create(root, { name = "Worktree capture", language = "c" }))
	local loaded = assert(Config.Load(root))
	Test.True(loaded.basics.git.enabled, "A .git pointer file should still identify a Git worktree")
	for _, entry in ipairs(loaded.layout.entries) do
		Test.False(entry.path == ".git", "The Git worktree pointer must not be captured in project metadata")
	end
	Cleanup(root)
end)

Test.Run("Project capture excludes .hmc and .git but keeps dotfiles and paths", function()
	local root = Root()
	Write(root .. "/.git/config", "repository")
	Write(root .. "/.gitignore", "build/\n")
	Write(root .. "/.env", "TOKEN=do-not-save\n")
	Write(root .. "/.env.example", "TOKEN=example\n")
	Write(root .. "/id_ed25519", "private-key-placeholder\n")
	Write(root .. "/src/nested/main.c", "int main(void) {}\n")
	assert(Config.Create(root, { name = "Capture", language = "c" }))
	local loaded = assert(Config.Load(root))
	local paths, contents = {}, {}
	for _, entry in ipairs(loaded.layout.entries) do paths[entry.path] = true; contents[entry.path] = entry.content end
	Test.False(paths[".hmc"] == true, ".hmc itself must not be captured")
	Test.False(paths[".hmc/secret.json"] == true, ".hmc contents must not be captured")
	Test.False(paths[".git"] == true, ".git itself must not be captured")
	Test.False(paths[".git/config"] == true, ".git contents must not be captured")
	Test.False(contents[".env"] ~= nil, "Environment secrets must not be captured")
	Test.False(contents["id_ed25519"] ~= nil, "Private keys must not be captured")
	Test.Equal("TOKEN=example\n", contents[".env.example"])
	Test.Equal("build/\n", contents[".gitignore"])
	Test.Equal("int main(void) {}\n", contents["src/nested/main.c"])
	Cleanup(root)
end)


Config.global_path = original_global_path
pcall(vim.fn.delete, global_test_root, "rf")
