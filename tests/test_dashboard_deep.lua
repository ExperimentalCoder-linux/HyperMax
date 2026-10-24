-- Deep public-API and lifecycle tests for the dashboard.
local Test = require("tests.testlib")
local Dashboard = require("hypermax.dashboard")
local FS = require("hypermax.filesystem")
local uv = vim.uv or vim.loop

local function New_Project()
	local root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
	vim.fn.mkdir(root .. "/.hmc", "p")
	vim.fn.mkdir(root .. "/src", "p")
	local basics = {
		version = 1,
		project = { name = "DeepTest", root = root, language = "c", manager = "native", creator = "tests", created_at = os.time(), entry_point = { file = "src/main.c", ["function"] = "main" } },
		git = { enabled = false },
	}
	local config = assert(io.open(root .. "/.hmc/basics.json", "w")); config:write(vim.json.encode(basics)); config:close()
	local main = assert(io.open(root .. "/src/main.c", "w")); main:write("int main(void) { return 0; }\n"); main:close()
	return root
end
local function Cleanup(root) if root then pcall(vim.fn.delete, root, "rf") end end
local function Open(root)
	local ok = Dashboard.Open(root)
	Test.True(ok, "Dashboard failed to open project")
	return Dashboard.Get_State()
end

local invalid_create_paths = {
	"", " ", ".", "..", "./x", "../x", "../../x", "/tmp/x", "~/x", "C:/x",
	"src/../x", "src/./x", "a/../../x", "\\\\server\\share", "C:\\temp\\x",
	"x\0y", "x\ny", "x\ty", "   /tmp/x", "~user/file", "//tmp/x", "../project/file",
}
for i, input in ipairs(invalid_create_paths) do
	Test.Run("Dashboard rejects unsafe creation path " .. i, function()
		local root = New_Project(); Open(root)
		local ok, path, err = Dashboard.Create("file", input)
		Test.False(ok); Test.Nil(path); Test.Type("string", err)
		Cleanup(root)
	end)
end

local valid_create_paths = {
	{ "src/one.c", "file" }, { "src/two.c", "file" }, { "include/player.h", "file" },
	{ "assets/image.png", "file" }, { "docs/read me.md", "file" }, { "src/deep/tree/main.c", "file" },
	{ "one", "folder" }, { "nested/two", "folder" }, { "assets/with spaces", "folder" },
	{ ".hidden", "file" }, { "folder.with.dots/file.ext", "file" }, { "unicode/é.txt", "file" },
}
for i, case in ipairs(valid_create_paths) do
	Test.Run("Dashboard creates valid path " .. i, function()
		local root = New_Project(); Open(root)
		local ok, path, err = Dashboard.Create(case[2], case[1])
		Test.True(ok, tostring(err)); Test.Not_Nil(path); Test.Not_Nil(uv.fs_stat(path))
		if case[2] == "folder" then Test.Equal("directory", uv.fs_stat(path).type) else Test.Equal("file", uv.fs_stat(path).type) end
		Test.True(FS.Is_Within(root, path))
		Test.Not_Nil(Dashboard.Get_State().line_by_path[FS.Normalize(path)], "Created item should be visible in the panel")
		Cleanup(root)
	end)
end

local sort_expected = { "file type", "modified", "created", "alphabetical", "file type", "modified", "created", "alphabetical" }
Test.Run("Dashboard sort cycling wraps and keeps mode names valid", function()
	local root = New_Project(); local state = Open(root)
	-- Sorting mode is intentionally persistent across projects. Reset it here
	-- so this test is independent of whichever tests ran before it.
	state.sort_mode = 1
	Dashboard.Refresh()
	for _, expected in ipairs(sort_expected) do
		local mode = Dashboard.Cycle_Sort()
		Test.Equal(expected, mode)
		Test.Equal(expected, state and ({ [1] = "alphabetical", [2] = "file type", [3] = "modified", [4] = "created" })[state.sort_mode])
	end
	Cleanup(root)
end)

local root_variants = { "src/main.c", "src", ".hmc/basics.json", "src/../src/main.c" }
for i, relative in ipairs(root_variants) do
	Test.Run("Dashboard finds project root from location " .. i, function()
		local root = New_Project()
		local found = Dashboard.Find_Project_Root(root .. "/" .. relative)
		Test.Equal(FS.Normalize(root), FS.Normalize(found))
		Cleanup(root)
	end)
end

Test.Run("Dashboard does not classify an arbitrary directory as a project", function()
	local root = vim.fn.fnamemodify(vim.fn.tempname(), ":p"); vim.fn.mkdir(root, "p")
	Test.False(Dashboard.Is_Project(root)); Cleanup(root)
end)
Test.Run("Dashboard detects a project with .hmc", function()
	local root = New_Project(); Test.True(Dashboard.Is_Project(root)); Cleanup(root)
end)
Test.Run("Dashboard rejects missing project on open", function()
	local root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
	Test.False(Dashboard.Open(root))
end)
Test.Run("Dashboard refresh keeps panel buffer valid", function()
	local root = New_Project(); local state = Open(root); local buf = state.buffer
	Dashboard.Refresh(); Test.True(vim.api.nvim_buf_is_valid(buf)); Test.Equal(buf, state.buffer)
	Cleanup(root)
end)
Test.Run("Dashboard refresh reloads newly created external files", function()
	local root = New_Project(); local state = Open(root)
	local path = root .. "/src/external.c"; local f = assert(io.open(path, "w")); f:write("x\n"); f:close()
	Dashboard.Refresh(); Test.Not_Nil(state.line_by_path[FS.Normalize(path)])
	Cleanup(root)
end)
Test.Run("Dashboard create reports existing path", function()
	local root = New_Project(); Open(root)
	local ok1 = Dashboard.Create("file", "src/existing.c"); Test.True(ok1)
	local ok2, _, err = Dashboard.Create("file", "src/existing.c"); Test.False(ok2); Test.True(err:find("Already exists", 1, true) ~= nil)
	Cleanup(root)
end)
Test.Run("Dashboard create reports unknown item kind", function()
	local root = New_Project(); Open(root)
	local ok, _, err = Dashboard.Create("symlink", "src/link"); Test.False(ok); Test.True(err:find("Unknown item type", 1, true) ~= nil)
	Cleanup(root)
end)
Test.Run("Dashboard create cancellation does not mutate tree", function()
	local root = New_Project(); local state = Open(root); local before = #state.tree
	local ok, _, err = Dashboard.Create("file", nil); Test.False(ok); Test.Equal("cancelled", err); Test.Equal(before, #state.tree)
	Cleanup(root)
end)
Test.Run("Dashboard Git init refreshes visible state", function()
	if vim.fn.executable("git") ~= 1 then print("[SKIP] Git unavailable"); return end
	local root = New_Project(); local state = Open(root)
	local ok = Dashboard.Initialize_Git(); Test.True(ok); Test.True(state.git.available); Test.Type("string", state.git.branch)
	local lines = vim.api.nvim_buf_get_lines(state.buffer, 0, -1, false)
	local text = table.concat(lines, "\n")
	Test.True(text:find("branch", 1, true) ~= nil, "Panel text should refresh with Git branch information")
	Cleanup(root)
end)
Test.Run("Dashboard Git status refresh sees newly created file", function()
	if vim.fn.executable("git") ~= 1 then print("[SKIP] Git unavailable"); return end
	local root = New_Project(); Open(root); Dashboard.Initialize_Git()
	local ok, path = Dashboard.Create("file", "src/git_seen.c"); Test.True(ok)
	local state = Dashboard.Get_State(); Test.Not_Nil(state.git.statuses[FS.Normalize(path)])
	Cleanup(root)
end)
Test.Run("Dashboard Git status refresh sees external change", function()
	if vim.fn.executable("git") ~= 1 then print("[SKIP] Git unavailable"); return end
	local root = New_Project(); Open(root); Dashboard.Initialize_Git()
	local path = root .. "/src/external_git.c"; local f = assert(io.open(path, "w")); f:write("x\n"); f:close()
	Dashboard.Refresh(); Test.Not_Nil(Dashboard.Get_State().git.statuses[FS.Normalize(path)])
	Cleanup(root)
end)
Test.Run("Dashboard close is safe repeatedly", function()
	local root = New_Project(); Open(root); Dashboard.Close(); Dashboard.Close(); Cleanup(root); Test.True(true)
end)
Test.Run("Dashboard state exposes stable public structures", function()
	local root = New_Project(); local state = Open(root)
	Test.Type("table", state); Test.Type("table", state.git); Test.Type("table", state.tree)
	Test.Type("table", state.items); Test.Type("table", state.line_by_path); Cleanup(root)
end)
Test.Run("Dashboard entry point metadata is retained after refresh", function()
	local root = New_Project(); local state = Open(root); Dashboard.Refresh()
	Test.Equal("src/main.c", state.metadata.entry_file); Test.Equal("main", state.metadata.entry_function); Cleanup(root)
end)
Test.Run("Dashboard render contains project name", function()
	local root = New_Project(); local state = Open(root)
	local text = table.concat(vim.api.nvim_buf_get_lines(state.buffer, 0, -1, false), "\n")
	Test.True(text:find("DeepTest", 1, true) ~= nil); Cleanup(root)
end)
Test.Run("Dashboard render contains file sorting label", function()
	local root = New_Project(); local state = Open(root)
	local text = table.concat(vim.api.nvim_buf_get_lines(state.buffer, 0, -1, false), "\n")
	Test.True(text:find("FILES", 1, true) ~= nil); Cleanup(root)
end)
Test.Run("Dashboard repeated open is idempotent for panel window", function()
	local root = New_Project(); local state = Open(root); local win = state.window
	Test.True(Dashboard.Open(root)); Test.Equal(win, state.window); Cleanup(root)
end)
Test.Run("Dashboard safe child API remains available through filesystem module", function()
	local root = New_Project(); local path = FS.Safe_Child(root, "src/new.c")
	Test.Equal(FS.Normalize(root .. "/src/new.c"), path); Cleanup(root)
end)
Test.Run("Dashboard path validation rejects project root itself", function()
	local root = New_Project(); local path = FS.Safe_Child(root, "")
	Test.Nil(path); Cleanup(root)
end)

-- The loop deliberately probes a broad set of boundary names independently.
local boundary_names = {
	"a", "z", "0", "9", "A", "Z", "_", "-", ".env", ".gitignore", "file.", "..name", "name..ext",
	"two words", "two  spaces", "é", "λ", "文件", "emoji-😀", "folder/name", "folder//name", "folder///name",
}
for i, name in ipairs(boundary_names) do
	Test.Run("Dashboard filesystem boundary name " .. i, function()
		local root = New_Project()
		local path, err = FS.Safe_Child(root, name)
		if name == "folder//name" or name == "folder///name" then
			Test.Not_Nil(path, tostring(err))
		else
			Test.Not_Nil(path, tostring(err))
		end
		Test.True(FS.Is_Within(root, path))
		Cleanup(root)
	end)
end

local function Find_Map(buffer, lhs)
	for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buffer, "n")) do
		if mapping.lhs == lhs then return mapping end
	end
	return nil
end

Test.Run("Dashboard file keymap invokes input callback and creates file", function()
	local root = New_Project(); local state = Open(root)
	local mapping = Find_Map(state.buffer, "a")
	Test.Not_Nil(mapping); Test.Type("function", mapping.callback)
	local old_input = vim.ui.input
	vim.ui.input = function(_, callback) callback("src/from_keymap.c") end
	local ok, err = pcall(mapping.callback)
	vim.ui.input = old_input
	Test.True(ok, tostring(err)); Test.Not_Nil(uv.fs_stat(root .. "/src/from_keymap.c"))
	Test.Not_Nil(state.line_by_path[FS.Normalize(root .. "/src/from_keymap.c")])
	Cleanup(root)
end)

Test.Run("Dashboard folder keymap invokes input callback and creates folder", function()
	local root = New_Project(); local state = Open(root)
	local mapping = Find_Map(state.buffer, "A")
	Test.Not_Nil(mapping); Test.Type("function", mapping.callback)
	local old_input = vim.ui.input
	vim.ui.input = function(_, callback) callback("src/from_keymap_folder") end
	local ok, err = pcall(mapping.callback)
	vim.ui.input = old_input
	Test.True(ok, tostring(err)); Test.Equal("directory", uv.fs_stat(root .. "/src/from_keymap_folder").type)
	Cleanup(root)
end)

Test.Run("Dashboard file keymap reports invalid path without throwing", function()
	local root = New_Project(); local state = Open(root)
	local mapping = Find_Map(state.buffer, "a")
	local old_input = vim.ui.input
	vim.ui.input = function(_, callback) callback("../escape.c") end
	local ok, err = pcall(mapping.callback)
	vim.ui.input = old_input
	Test.True(ok, tostring(err)); Test.Nil(uv.fs_stat(FS.Normalize(root .. "/../escape.c")))
	Cleanup(root)
end)

Test.Run("Dashboard Git keymap initializes and refreshes the panel", function()
	if vim.fn.executable("git") ~= 1 then print("[SKIP] Git unavailable"); return end
	local root = New_Project(); local state = Open(root)
	local mapping = Find_Map(state.buffer, "G")
	Test.Not_Nil(mapping); Test.Type("function", mapping.callback)
	local ok, err = pcall(mapping.callback)
	Test.True(ok, tostring(err)); Test.True(state.git.available)
	local text = table.concat(vim.api.nvim_buf_get_lines(state.buffer, 0, -1, false), "\n")
	Test.True(text:find("Changes", 1, true) ~= nil)
	Cleanup(root)
end)

Test.Run("Dashboard refresh action keymap is installed", function()
	local root = New_Project(); local state = Open(root)
	Test.Type("function", Find_Map(state.buffer, "r").callback); Cleanup(root)
end)

Test.Run("Dashboard sort action keymap is installed", function()
	local root = New_Project(); local state = Open(root)
	Test.Type("function", Find_Map(state.buffer, "s").callback); Cleanup(root)
end)

Test.Run("Dashboard Git action keymap is installed", function()
	local root = New_Project(); local state = Open(root)
	Test.Type("function", Find_Map(state.buffer, "g").callback); Cleanup(root)
end)

Test.Run("Dashboard close keymap is installed", function()
	local root = New_Project(); local state = Open(root)
	Test.Type("function", Find_Map(state.buffer, "q").callback); Cleanup(root)
end)

Test.Run("Dashboard alphabetical sorting orders directories and files", function()
	local root = New_Project()
	vim.fn.mkdir(root .. "/zdir", "p"); vim.fn.mkdir(root .. "/adir", "p")
	for _, name in ipairs({ "z.txt", "a.txt", "m.txt" }) do local f = assert(io.open(root .. "/" .. name, "w")); f:write("x"); f:close() end
	local state = Open(root); state.sort_mode = 1; Dashboard.Refresh()
	local names = {}; for _, entry in ipairs(state.tree) do names[#names + 1] = entry.name end
	Test.Equal("adir", names[1]); Test.Equal("src", names[2]); Test.Equal("zdir", names[3])
	Test.Equal("a.txt", names[4]); Test.Equal("m.txt", names[5]); Test.Equal("z.txt", names[6])
	Cleanup(root)
end)

Test.Run("Dashboard file-type sorting groups extensions", function()
	local root = New_Project()
	for _, name in ipairs({ "z.h", "a.cpp", "b.c", "plain" }) do local f = assert(io.open(root .. "/" .. name, "w")); f:write("x"); f:close() end
	local state = Open(root); state.sort_mode = 2; Dashboard.Refresh()
	local files = {}; for _, entry in ipairs(state.tree) do if entry.type == "file" then files[#files + 1] = entry.name end end
	Test.Equal("plain", files[1]); Test.Equal("b.c", files[2]); Test.Equal("a.cpp", files[3]); Test.Equal("z.h", files[4])
	Cleanup(root)
end)

Test.Run("Dashboard modified sorting puts newest file first", function()
	local root = New_Project()
	for _, name in ipairs({ "older.txt", "newer.txt" }) do local f = assert(io.open(root .. "/" .. name, "w")); f:write(name); f:close() end
	if not uv.fs_utime then print("[SKIP] uv.fs_utime unavailable"); Cleanup(root); return end
	uv.fs_utime(root .. "/older.txt", 1000, 1000)
	uv.fs_utime(root .. "/newer.txt", 2000, 2000)
	local state = Open(root); state.sort_mode = 3; Dashboard.Refresh()
	local files = {}; for _, entry in ipairs(state.tree) do if entry.type == "file" then files[#files + 1] = entry.name end end
	Test.Equal("newer.txt", files[1]); Test.Equal("older.txt", files[2])
	Cleanup(root)
end)

Test.Run("Dashboard created sorting is safe with filesystem timestamp fallbacks", function()
	local root = New_Project(); local state = Open(root)
	state.sort_mode = 4
	local ok, err = pcall(Dashboard.Refresh)
	Test.True(ok, tostring(err)); Test.Equal("created", ({ [1] = "alphabetical", [2] = "file type", [3] = "modified", [4] = "created" })[state.sort_mode])
	Cleanup(root)
end)
