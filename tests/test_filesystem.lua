-- Deep edge-case tests for project-relative file/folder creation.
local Test = require("tests.testlib")
local FS = require("hypermax.filesystem")
local uv = vim.uv or vim.loop

local function New_Root()
	local root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
	vim.fn.mkdir(root, "p")
	return root
end
local function Cleanup(root) if root then pcall(vim.fn.delete, root, "rf") end end
local function Exists(path) return uv.fs_lstat(path) ~= nil end

local unsafe = {
	{ "empty", "" }, { "spaces only", "   " }, { "dot", "." }, { "dot slash", "./file" },
	{ "parent", ".." }, { "parent prefix", "../escape" }, { "nested parent", "src/../../escape" },
	{ "absolute root", "/tmp/escape" }, { "tilde home", "~/escape" }, { "windows drive", "C:/escape" },
	{ "windows drive lower", "d:\\escape" }, { "backslash traversal", "..\\escape" },
	{ "embedded traversal", "src/../escape" }, { "nested dot", "src/./file" },
	{ "nul byte", "src/\0bad" }, { "newline", "src/bad\nname" }, { "tab", "src/bad\tname" },
	{ "escape twice", "../../../../escape" }, { "leading whitespace absolute", " /tmp/escape" },
	{ "only slash", "/" }, { "root slash", "//server/share" },
}
for _, case in ipairs(unsafe) do
	Test.Run("Filesystem rejects unsafe path: " .. case[1], function()
		local root = New_Root()
		local path, err = FS.Safe_Child(root, case[2])
		Test.Nil(path, "Unsafe input should not produce a path")
		Test.Type("string", err, "Unsafe path should explain the rejection")
		Cleanup(root)
	end)
end

local safe = {
	"main.c", "src/main.c", "include/player.h", "assets/texture.png", "a b/file name.txt",
	"folder.with.dots/file.ext", "under_score/file_name.c", "dash-name/file-name.c", "unicode/é.txt",
	"literal; punctuation/file $(name).txt", "leading-dash/-main.c",
	"UPPER/FILE.C", "deep/one/two/three.txt", "folder/123", "file..name.c", "space at end /name.txt",
}
for index, input in ipairs(safe) do
	Test.Run("Filesystem accepts safe relative path " .. index, function()
		local root = New_Root()
		local path, err = FS.Safe_Child(root, input)
		Test.Not_Nil(path, "Safe path rejected: " .. tostring(err))
		Test.True(FS.Is_Within(root, path), "Returned path must be inside root")
		Test.True(path:sub(1, #FS.Normalize(root) + 1) == FS.Normalize(root) .. "/")
		Cleanup(root)
	end)
end

local create_cases = {
	{ "simple file", "file", "main.c", "file" },
	{ "nested file", "file", "src/game/main.c", "file" },
	{ "file with spaces", "file", "assets/my texture.png", "file" },
	{ "unicode file", "file", "src/é.c", "file" },
	{ "simple folder", "folder", "src", "directory" },
	{ "nested folder", "folder", "src/game/player", "directory" },
	{ "folder with spaces", "folder", "assets/my textures", "directory" },
	{ "dot file", "file", ".gitignore", "file" },
	{ "folder with dot", "folder", "include.v2", "directory" },
	{ "multiple nested file parents", "file", "one/two/three/four.txt", "file" },
	{ "multiple nested folder parents", "folder", "one/two/three/four", "directory" },
}
for _, case in ipairs(create_cases) do
	Test.Run("Filesystem creates " .. case[1], function()
		local root = New_Root()
		local ok, path, err = FS.Create(root, case[2], case[3])
		Test.True(ok, "Creation failed: " .. tostring(err))
		Test.Not_Nil(path)
		local stat = uv.fs_stat(path)
		Test.Not_Nil(stat, "Created path must exist")
		Test.Equal(case[4], stat.type)
		Cleanup(root)
	end)
end

local failures = {
	{ "unknown type", "unknown", "file.txt" },
	{ "missing root", "file", "file.txt", nil },
	{ "non-string input", "file", 42 },
}
for _, case in ipairs(failures) do
	Test.Run("Filesystem handles invalid request: " .. case[1], function()
		local root = New_Root()
		local ok, path, err
		if case[1] == "missing root" then
			ok, path, err = FS.Create(nil, case[2], case[3])
		else
			ok, path, err = FS.Create(root, case[2], case[3])
		end
		Test.False(ok)
		Test.Nil(path)
		Test.Type("string", err)
		Cleanup(root)
	end)
end

Test.Run("Filesystem treats cancellation as non-error", function()
	local root = New_Root()
	local ok, path, err = FS.Create(root, "file", nil)
	Test.False(ok); Test.Nil(path); Test.Equal("cancelled", err)
	Cleanup(root)
end)

Test.Run("Filesystem refuses to overwrite an existing file", function()
	local root = New_Root(); local path = root .. "/existing.txt"
	local f = assert(io.open(path, "w")); f:write("keep"); f:close()
	local ok, _, err = FS.Create(root, "file", "existing.txt")
	Test.False(ok); Test.True(err:find("Already exists", 1, true) ~= nil)
	local read = assert(io.open(path, "r")); Test.Equal("keep", read:read("*a")); read:close()
	Cleanup(root)
end)

Test.Run("Filesystem refuses to overwrite an existing folder", function()
	local root = New_Root(); vim.fn.mkdir(root .. "/existing", "p")
	local ok, _, err = FS.Create(root, "folder", "existing")
	Test.False(ok); Test.True(err:find("Already exists", 1, true) ~= nil)
	Cleanup(root)
end)

Test.Run("Filesystem refuses a file where a parent folder is expected", function()
	local root = New_Root(); local f = assert(io.open(root .. "/blocker", "w")); f:close()
	local ok, _, err = FS.Create(root, "file", "blocker/child.txt")
	Test.False(ok); Test.Type("string", err)
	Cleanup(root)
end)

Test.Run("Filesystem normalizes root trailing slash", function()
	local root = New_Root()
	local path, err = FS.Safe_Child(root .. "/", "src/main.c")
	Test.Not_Nil(path, tostring(err)); Test.True(FS.Is_Within(root, path))
	Cleanup(root)
end)

Test.Run("Filesystem does not consider root itself a child", function()
	local root = New_Root()
	Test.False(FS.Is_Within(root, root))
	Cleanup(root)
end)

Test.Run("Filesystem rejects sibling sharing root prefix", function()
	local root = New_Root()
	Test.False(FS.Is_Within(root, root .. "-escape/file"))
	Cleanup(root)
end)

Test.Run("Filesystem handles a root path with spaces", function()
	local root = New_Root() .. " root with spaces"
	vim.fn.mkdir(root, "p")
	local ok, path, err = FS.Create(root, "file", "src/main.c")
	Test.True(ok, tostring(err)); Test.True(Exists(path))
	Cleanup(root)
end)

Test.Run("Filesystem rejects symlink escape when symlink support is available", function()
	local root, outside = New_Root(), New_Root()
	local link = root .. "/outside"
	local ok = pcall(uv.fs_symlink, outside, link, {})
	if ok and uv.fs_lstat(link) then
		local path, err = FS.Safe_Child(root, "outside/escape.txt")
		Test.Nil(path); Test.Type("string", err)
	else
		print("[SKIP] symlink creation is unavailable on this platform")
	end
	Cleanup(root); Cleanup(outside)
end)

-- These table-driven cases are intentionally separate test records so a failure
-- identifies the exact edge case instead of hiding behind a broad aggregate.
Test.Run("Filesystem normalization is idempotent for common paths", function()
	local root = New_Root()
	for _, path in ipairs({ root, root .. "/", root .. "/src/../src", root .. "/./src" }) do
		local first = FS.Normalize(path)
		Test.Not_Nil(first)
		Test.Equal(first, FS.Normalize(first))
	end
	Cleanup(root)
end)


Test.Run("Filesystem refuses dashboard deletion of protected metadata", function()
	local root = New_Root()
	vim.fn.mkdir(root .. "/.hmc", "p")
	local f = assert(io.open(root .. "/.hmc/basics.json", "w")); f:write("{}"); f:close()
	local ok, err = FS.Delete(root, ".hmc/basics.json")
	Test.False(ok)
	Test.Type("string", err)
	Test.True(Exists(root .. "/.hmc/basics.json"), "Protected metadata must remain")
	Cleanup(root)
end)

Test.Run("Filesystem refuses dashboard moves into protected metadata", function()
	local root = New_Root()
	vim.fn.mkdir(root .. "/.hmc", "p")
	local f = assert(io.open(root .. "/notes.txt", "w")); f:write("keep"); f:close()
	local ok, _, err = FS.Move(root, "notes.txt", ".hmc/notes.txt")
	Test.False(ok)
	Test.Type("string", err)
	Test.True(Exists(root .. "/notes.txt"), "Source must remain after refused move")
	Cleanup(root)
end)

Test.Run("Filesystem refuses dashboard moves out of protected metadata", function()
	local root = New_Root()
	vim.fn.mkdir(root .. "/.hmc", "p")
	local f = assert(io.open(root .. "/.hmc/basics.json", "w")); f:write("{}"); f:close()
	local ok, _, err = FS.Move(root, ".hmc/basics.json", "basics.json")
	Test.False(ok)
	Test.Type("string", err)
	Test.True(Exists(root .. "/.hmc/basics.json"), "Protected metadata must remain")
	Cleanup(root)
end)
