-- Tests for the per-project task board and run configuration store.
local Test = require("tests.testlib")
local Config = require("hypermax.project_config")
local Flow = require("hypermax.flow")

local original_global_path = Config.global_path
local global_root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
Config.global_path = global_root .. "/hypermax/config.json"

local function Root()
	local root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
	vim.fn.mkdir(root, "p")
	local ok, err = Config.Create(root, { name = "FlowTest", language = "lua", manager = "native" })
	assert(ok, tostring(err))
	vim.fn.mkdir(root .. "/build", "p")
	return root
end

local function Cleanup(root)
	if root then pcall(vim.fn.delete, root, "rf") end
end

Test.Run("Flow normalizes malformed and unsupported workspace data", function()
	local data = Flow.Normalize_Data({
		version = 99,
		tasks = {
			{ id = "one", title = "  Ship feature  ", status = "blocked", priority = "urgent" },
			{ id = "one", title = "duplicate" },
			"invalid",
		},
		runners = {
			{ id = "build", name = "Build", command = "make", cwd = "." },
			{ id = "empty", name = "Empty", command = " " },
		},
	})
	Test.Equal(1, data.version)
	Test.Equal(1, #data.tasks)
	Test.Equal("Ship feature", data.tasks[1].title)
	Test.Equal("todo", data.tasks[1].status)
	Test.Equal("normal", data.tasks[1].priority)
	Test.Equal(1, #data.runners)
end)

Test.Run("Flow task lifecycle persists in project metadata", function()
	local root = Root()
	local ok, task = Flow.Add_Task(root, "Implement parser", "Add tests too", "high")
	Test.True(ok, tostring(task))
	Test.Equal("Implement parser", task.title)
	local loaded, err = Flow.Load(root)
	Test.Not_Nil(loaded, tostring(err))
	Test.Equal(1, #loaded.tasks)
	Test.Equal("Add tests too", loaded.tasks[1].detail)
	local updated, update_error = Flow.Update_Task(root, task.id, { status = "doing", priority = "normal", title = "Finish parser" })
	Test.True(updated, tostring(update_error))
	loaded = assert(Flow.Load(root))
	Test.Equal("doing", loaded.tasks[1].status)
	Test.Equal("normal", loaded.tasks[1].priority)
	Test.Equal("Finish parser", loaded.tasks[1].title)
	local summary = assert(Flow.Get_Summary(root))
	Test.Equal(1, summary.doing)
	Test.Equal(0, summary.todo)
	local deleted, delete_error = Flow.Delete_Task(root, task.id)
	Test.True(deleted, tostring(delete_error))
	loaded = assert(Flow.Load(root))
	Test.Equal(0, #loaded.tasks)
	Cleanup(root)
end)

Test.Run("Flow pinning persists and keeps tasks in the selected status", function()
	local root = Root()
	local ok, task = Flow.Add_Task(root, "Pinned task", "Keep this visible", "high")
	Test.True(ok, tostring(task))
	local pinned, result = Flow.Toggle_Task_Pinned(root, task.id)
	Test.True(pinned, tostring(result))
	Test.True(result.pinned)
	local loaded = assert(Flow.Load(root))
	Test.True(loaded.tasks[1].pinned)
	Test.Not_Nil(loaded.tasks[1].pinned_at)
	local moved, move_error = Flow.Update_Task(root, task.id, { status = "doing" })
	Test.True(moved, tostring(move_error))
	loaded = assert(Flow.Load(root))
	Test.Equal("doing", loaded.tasks[1].status)
	Test.True(loaded.tasks[1].pinned)
	local unpinned, unpin_result = Flow.Toggle_Task_Pinned(root, task.id)
	Test.True(unpinned, tostring(unpin_result))
	Test.False(unpin_result.pinned)
	loaded = assert(Flow.Load(root))
	Test.False(loaded.tasks[1].pinned)
	Test.Nil(loaded.tasks[1].pinned_at)
	Cleanup(root)
end)

Test.Run("Flow refuses empty task titles and missing projects", function()
	local root = Root()
	local ok, err = Flow.Add_Task(root, "   ")
	Test.False(ok)
	Test.True(tostring(err):find("cannot be empty", 1, true) ~= nil)
	local missing = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
	local missing_ok = Flow.Add_Task(missing, "not saved")
	Test.False(missing_ok)
	Cleanup(root)
end)

Test.Run("Flow run configurations validate paths and persist safely", function()
	local root = Root()
	local ok, runner = Flow.Add_Runner(root, "Build debug", "cmake --build build", "build", "Build the debug target")
	Test.True(ok, tostring(runner))
	local loaded, err = Flow.Load(root)
	Test.Not_Nil(loaded, tostring(err))
	Test.Equal(1, #loaded.runners)
	Test.Equal("build", loaded.runners[1].cwd)
	Test.Equal("cmake --build build", loaded.runners[1].command)
	local updated, update_error = Flow.Update_Runner(root, runner.id, { name = "Build release", command = "cmake --build build --config Release" })
	Test.True(updated, tostring(update_error))
	loaded = assert(Flow.Load(root))
	Test.Equal("Build release", loaded.runners[1].name)
	local deleted, delete_error = Flow.Delete_Runner(root, runner.id)
	Test.True(deleted, tostring(delete_error))
	loaded = assert(Flow.Load(root))
	Test.Equal(0, #loaded.runners)
	Cleanup(root)
end)

for _, cwd in ipairs({ "../outside", "../../", "/tmp", "C:/Windows", "nested/../../escape" }) do
	Test.Run("Flow rejects unsafe runner directory: " .. cwd, function()
		local root = Root()
		local ok = Flow.Add_Runner(root, "Unsafe", "echo test", cwd)
		Test.False(ok)
		Cleanup(root)
	end)
end

Test.Run("Flow rejects a runner directory that symlinks outside the project", function()
	local root = Root()
	local uv = vim.uv or vim.loop
	local outside = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
	vim.fn.mkdir(outside, "p")
	local linked = uv.fs_symlink(outside, root .. "/build/external", { dir = true })
	if linked then
		local ok, err = Flow.Add_Runner(root, "Escaping runner", "echo unsafe", "build/external")
		Test.False(ok, tostring(err))
	else
		Test.True(true, "Filesystem does not permit directory symlinks in this test environment")
	end
	pcall(vim.fn.delete, outside, "rf")
	Cleanup(root)
end)

Test.Run("Flow refuses a symlinked .hmc metadata directory", function()
	local root = Root()
	local uv = vim.uv or vim.loop
	local outside_metadata = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
	local moved, move_error = uv.fs_rename(root .. "/.hmc", outside_metadata)
	if moved then
		local linked = uv.fs_symlink(outside_metadata, root .. "/.hmc", { dir = true })
		if linked then
			local saved = Flow.Save(root, { tasks = {}, runners = {} })
			Test.False(saved, "Flow must not write metadata through a symlink")
		end
		pcall(uv.fs_unlink, root .. "/.hmc")
		pcall(vim.fn.delete, outside_metadata, "rf")
	else
		Test.True(false, "Could not prepare symlink safety test: " .. tostring(move_error))
	end
	Cleanup(root)
end)

Test.Run("Flow refuses a symlinked workspace data file", function()
	local root = Root()
	local uv = vim.uv or vim.loop
	local outside_data = vim.fn.tempname() .. ".json"
	local file = assert(io.open(outside_data, "w"))
	file:write('{"tasks":[],"runners":[]}\n')
	file:close()
	local linked = uv.fs_symlink(outside_data, root .. "/.hmc/workspace.json")
	if linked then
		local loaded, err = Flow.Load(root)
		Test.Nil(loaded)
		Test.True(tostring(err):find("symlinked", 1, true) ~= nil)
	else
		Test.True(true, "Filesystem does not permit file symlinks in this test environment")
	end
	pcall(uv.fs_unlink, root .. "/.hmc/workspace.json")
	pcall(os.remove, outside_data)
	Cleanup(root)
end)

Test.Run("Flow refuses unsupported project-data writes", function()
	local root = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
	local ok = Flow.Save(root, { tasks = {} })
	Test.False(ok)
end)

Config.global_path = original_global_path
pcall(vim.fn.delete, global_root, "rf")
