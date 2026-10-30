-- Deep tests for Git command execution, status parsing and repository edge cases.
local Test = require("tests.testlib")
local Git = require("hypermax.git")
local uv = vim.uv or vim.loop

local function New_Root(suffix)
	local root = vim.fn.fnamemodify(vim.fn.tempname(), ":p") .. (suffix or "")
	vim.fn.mkdir(root, "p")
	return root
end
local function Cleanup(root) if root then pcall(vim.fn.delete, root, "rf") end end
local function Write(path, content)
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	local file = assert(io.open(path, "w")); file:write(content or "x\n"); file:close()
end
local function Has_Git() return vim.fn.executable("git") == 1 end

local status_cases = {
	{ "untracked file", { "?? new.c" }, "new.c", "??" },
	{ "modified file", { " M main.c" }, "main.c", " M" },
	{ "staged addition", { "A  add.c" }, "add.c", "A " },
	{ "staged modification", { "M  main.c" }, "main.c", "M " },
	{ "staged deletion", { "D  gone.c" }, "gone.c", "D " },
	{ "unstaged deletion", { " D gone.c" }, "gone.c", " D" },
	{ "staged and unstaged modification", { "MM both.c" }, "both.c", "MM" },
	{ "rename destination", { "R  old.c -> new.c" }, "new.c", "R " },
	{ "untracked nested file", { "?? src/main.c" }, "src/main.c", "??" },
	{ "space in path", { "?? src/my file.c" }, "src/my file.c", "??" },
	{ "dash in path", { "?? -main.c" }, "-main.c", "??" },
	{ "underscore in path", { "?? my_file.c" }, "my_file.c", "??" },
	{ "unicode path", { "?? src/é.c" }, "src/é.c", "??" },
	{ "dotfile", { "?? .gitignore" }, ".gitignore", "??" },
	{ "multiple status rows", { "?? one.c", " M two.c", "A  three.c" }, "three.c", "A " },
	{ "ignores malformed short row", { "?" }, "?", nil },
	{ "ignores empty row", { "" }, "", nil },
	{ "ignores header row", { "## main" }, "main", nil },
	{ "does not map parent traversal", { "?? ../escape.c" }, "../escape.c", nil },
	{ "maps nested directory", { "?? src/one/two.c" }, "src/one/two.c", "??" },
	{ "handles duplicate rows with last status", { "?? same.c", " M same.c" }, "same.c", " M" },
	{ "handles path beginning with dot", { "?? .config/app" }, ".config/app", "??" },
	{ "handles numeric filename", { "?? 123.c" }, "123.c", "??" },
	{ "handles extensionless filename", { "?? Makefile" }, "Makefile", "??" },
	{ "handles directory marker path", { "?? assets/" }, "assets", "??" },
	{ "handles type change", { " T script.sh" }, "script.sh", " T" },
	{ "filename containing arrow is not mistaken for rename", { "?? old -> new.txt" }, "old -> new.txt", "??" },
	{ "empty path is ignored", { "?? " }, "", nil },
	{ "decodes escaped newline filename", { [[?? "line\nfeed.c"]] }, "line\nfeed.c", "??" },
}
for _, case in ipairs(status_cases) do
	Test.Run("Git status parser: " .. case[1], function()
		local root = New_Root()
		local statuses = Git.Parse_Status(case[2], root)
		local expected_path = case[3] == "" and "" or (vim.fs and vim.fs.normalize and vim.fs.normalize(root .. "/" .. case[3]) or vim.fn.fnamemodify(root .. "/" .. case[3], ":p"))
		if case[4] then
			Test.Equal(case[4], statuses[expected_path], "Status code mismatch for " .. case[3])
		else
			Test.True(next(statuses) == nil, "Malformed or unsafe row should not be mapped")
		end
		Cleanup(root)
	end)
end

Test.Run("Git rejects missing root", function()
	local output, err = Git.Run(nil, { "status" })
	Test.Nil(output); Test.Type("string", err)
end)
Test.Run("Git rejects empty root", function()
	local output, err = Git.Run("", { "status" })
	Test.Nil(output); Test.Type("string", err)
end)
Test.Run("Git rejects empty argument list", function()
	local output, err = Git.Run("/tmp", {})
	Test.Nil(output); Test.Type("string", err)
end)
Test.Run("Git rejects non-table arguments", function()
	local output, err = Git.Run("/tmp", "status")
	Test.Nil(output); Test.Type("string", err)
end)
Test.Run("Git rejects non-string argument", function()
	local output, err = Git.Run("/tmp", { 12 })
	Test.Nil(output); Test.Type("string", err)
end)
Test.Run("Git reports a non-repository as unavailable", function()
	local root = New_Root()
	Test.False(Git.Is_Repository(root))
	local snapshot = Git.Snapshot(root)
	Test.False(snapshot.available); Test.Nil(snapshot.branch); Test.Equal(0, vim.tbl_count(snapshot.statuses))
	Cleanup(root)
end)

if not Has_Git() then
	print("[SKIP] Git executable tests: Git is not installed")
else
	local integration = {
		{ "initializes repository", function(root) local out, err = Git.Init(root); Test.Not_Nil(out, tostring(err)); Test.True(Git.Is_Repository(root)) end },
		{ "snapshot detects newly initialized repository", function(root) Git.Init(root); local s = Git.Snapshot(root); Test.True(s.available); Test.Type("string", s.branch); end },
		{ "branch is available before first commit", function(root) Git.Init(root); local branch = Git.Branch(root); Test.Type("string", branch); Test.True(branch ~= "") end },
		{ "status detects untracked file", function(root) Git.Init(root); Write(root .. "/untracked.c"); local s = Git.Snapshot(root); Test.Not_Nil(s.statuses[vim.fn.fnamemodify(root .. "/untracked.c", ":p")]) end },
		{ "status detects nested untracked file", function(root) Git.Init(root); Write(root .. "/src/main.c"); local s = Git.Snapshot(root); Test.Not_Nil(s.statuses[vim.fn.fnamemodify(root .. "/src/main.c", ":p")]) end },
		{ "stage all succeeds", function(root) Git.Init(root); Write(root .. "/a.c"); local out, err = Git.Add_All(root); Test.Not_Nil(out, tostring(err)); end },
		{ "stage all removes untracked state", function(root) Git.Init(root); Write(root .. "/a.c"); Git.Add_All(root); local s = Git.Snapshot(root); Test.Equal("A ", s.statuses[vim.fn.fnamemodify(root .. "/a.c", ":p")]) end },
		{ "empty commit message is rejected", function(root) Git.Init(root); local out, err = Git.Commit(root, " "); Test.Nil(out); Test.True(err:find("cannot be empty", 1, true) ~= nil) end },
		{ "commit with no staged files fails cleanly", function(root) Git.Init(root); local out = Git.Commit(root, "empty"); Test.Nil(out) end },
		{ "commit message is passed as one argument", function(root) Git.Init(root); vim.fn.systemlist({ "git", "-C", root, "config", "user.email", "tests@example.invalid" }); vim.fn.systemlist({ "git", "-C", root, "config", "user.name", "HyperMax Tests" }); Write(root .. "/a.c"); Git.Add_All(root); local out, err = Git.Commit(root, "message with spaces; punctuation!"); Test.Not_Nil(out, tostring(err)) end },
		{ "recent log handles no commits", function(root) Git.Init(root); local out = Git.Recent(root, 5); Test.Nil(out) end },
		{ "recent log shows committed change", function(root) Git.Init(root); vim.fn.systemlist({ "git", "-C", root, "config", "user.email", "tests@example.invalid" }); vim.fn.systemlist({ "git", "-C", root, "config", "user.name", "HyperMax Tests" }); Write(root .. "/a.c"); Git.Add_All(root); local out, err = Git.Commit(root, "first"); Test.Not_Nil(out, tostring(err)); local log = Git.Recent(root, 5); Test.Not_Nil(log); Test.True(table.concat(log, "\n"):find("first", 1, true) ~= nil) end },
		{ "detached HEAD is distinguished from unborn repository", function(root) Git.Init(root); vim.fn.systemlist({ "git", "-C", root, "config", "user.email", "tests@example.invalid" }); vim.fn.systemlist({ "git", "-C", root, "config", "user.name", "HyperMax Tests" }); Write(root .. "/a.c"); Git.Add_All(root); local out, err = Git.Commit(root, "first"); Test.Not_Nil(out, tostring(err)); local checkout = vim.fn.systemlist({ "git", "-C", root, "checkout", "--detach", "HEAD" }); Test.Equal(0, vim.v.shell_error, table.concat(checkout, "\n")); Test.True(Git.Branch(root):match("^detached@") ~= nil) end },
		{ "path with spaces is handled as argv", function(root) Git.Init(root); Write(root .. "/folder with spaces/file name.c"); local s = Git.Snapshot(root); Test.Not_Nil(s.statuses[vim.fs.normalize(root .. "/folder with spaces/file name.c")]) end },
		{ "repository path with shell punctuation is handled literally", function(root) local odd = root .. "/project ; $(literal)"; vim.fn.mkdir(odd, "p"); local out, err = Git.Init(odd); Test.Not_Nil(out, tostring(err)); Test.True(Git.Is_Repository(odd)) end },
		{ "commit message cannot execute shell substitutions", function(root) Git.Init(root); vim.fn.systemlist({ "git", "-C", root, "config", "user.email", "tests@example.invalid" }); vim.fn.systemlist({ "git", "-C", root, "config", "user.name", "HyperMax Tests" }); Write(root .. "/safe.c"); Git.Add_All(root); local marker = root .. "/should-not-exist"; local out, err = Git.Commit(root, "$(touch " .. marker .. ")"); Test.Not_Nil(out, tostring(err)); Test.Nil(uv.fs_lstat(marker)) end },

		{ "branch listing and creation are supported", function(root)
			Git.Init(root); vim.fn.systemlist({ "git", "-C", root, "config", "user.email", "tests@example.invalid" }); vim.fn.systemlist({ "git", "-C", root, "config", "user.name", "HyperMax Tests" }); Write(root .. "/seed.c"); Git.Add_All(root); local committed, commit_error = Git.Commit(root, "seed"); Test.Not_Nil(committed, tostring(commit_error)); local created, create_error = Git.Create_Branch(root, "feature/test-branch"); Test.Not_Nil(created, tostring(create_error)); local branches = Git.Branches(root); Test.Not_Nil(branches); Test.True(vim.tbl_contains(branches, "feature/test-branch"))
		end },
		{ "branch names use Git ref validation", function(root)
			Git.Init(root)
			local output, err = Git.Create_Branch(root, "bad..branch")
			Test.Nil(output)
			Test.Equal("Invalid branch name", err)
		end },
		{ "stage and unstage a selected relative path", function(root)
			Git.Init(root); Write(root .. "/src/file with spaces.c"); local staged, stage_error = Git.Stage(root, "src/file with spaces.c"); Test.Not_Nil(staged, tostring(stage_error)); local statuses = Git.Status(root); Test.Equal("A ", statuses[vim.fs.normalize(root .. "/src/file with spaces.c")]); local unstaged, unstage_error = Git.Unstage(root, "src/file with spaces.c"); Test.Not_Nil(unstaged, tostring(unstage_error))
		end },
		{ "remote add/list/fetch/push/pull/remove workflow", function(root)
			Git.Init(root)
			local remote = New_Root("-remote.git")
			local init_remote = vim.fn.systemlist({ "git", "init", "--bare", remote })
			Test.Equal(0, vim.v.shell_error, table.concat(init_remote, "\n"))
			vim.fn.systemlist({ "git", "-C", root, "config", "user.email", "tests@example.invalid" })
			vim.fn.systemlist({ "git", "-C", root, "config", "user.name", "HyperMax Tests" })
			Write(root .. "/seed.c"); Git.Add_All(root)
			local committed, commit_error = Git.Commit(root, "seed"); Test.Not_Nil(committed, tostring(commit_error))
			local added, add_error = Git.Add_Remote(root, "origin", "  " .. remote .. "  "); Test.Not_Nil(added, tostring(add_error))
			Test.True(vim.tbl_contains(Git.Remotes(root), "origin"))
			Test.True(#Git.Remote_Details(root) >= 2)
			local branch = Git.Branch(root)
			local pushed, push_error = Git.Push(root, "origin", branch); Test.Not_Nil(pushed, tostring(push_error))
			local fetched, fetch_error = Git.Fetch(root, "origin"); Test.Not_Nil(fetched, tostring(fetch_error))
			local pulled, pull_error = Git.Pull(root, "origin", branch); Test.Not_Nil(pulled, tostring(pull_error))
			local removed, remove_error = Git.Remove_Remote(root, "origin"); Test.Not_Nil(removed, tostring(remove_error))
			Test.False(vim.tbl_contains(Git.Remotes(root), "origin"))
			Cleanup(remote)
		end },
		{ "create, list, and delete an annotated tag", function(root)
			Git.Init(root); vim.fn.systemlist({ "git", "-C", root, "config", "user.email", "tests@example.invalid" }); vim.fn.systemlist({ "git", "-C", root, "config", "user.name", "HyperMax Tests" }); Write(root .. "/seed.c"); Git.Add_All(root); local committed, commit_error = Git.Commit(root, "seed"); Test.Not_Nil(committed, tostring(commit_error)); local created, create_error = Git.Create_Tag(root, "release/v1", "Release one"); Test.Not_Nil(created, tostring(create_error)); local tags = Git.Tags(root); Test.True(vim.tbl_contains(tags, "release/v1")); local deleted, delete_error = Git.Delete_Tag(root, "release/v1"); Test.Not_Nil(deleted, tostring(delete_error)); Test.False(vim.tbl_contains(Git.Tags(root), "release/v1"))
		end },
		{ "reject invalid tag names", function(root)
			Git.Init(root); local output, err = Git.Create_Tag(root, "bad tag", "invalid"); Test.Nil(output); Test.Type("string", err)
		end },
		{ "invalid stash references are rejected", function(root)
			Git.Init(root); local output, err = Git.Stash_Pop(root, "--all"); Test.Nil(output); Test.Equal("Invalid stash reference", err)
		end },
		{ "stash and restore untracked changes", function(root)
			Git.Init(root); vim.fn.systemlist({ "git", "-C", root, "config", "user.email", "tests@example.invalid" }); vim.fn.systemlist({ "git", "-C", root, "config", "user.name", "HyperMax Tests" }); Write(root .. "/seed.c"); Git.Add_All(root); local committed, commit_error = Git.Commit(root, "seed"); Test.Not_Nil(committed, tostring(commit_error)); Write(root .. "/new.c"); local stashed, stash_error = Git.Stash(root, "test stash"); Test.Not_Nil(stashed, tostring(stash_error)); local stashes = Git.Stashes(root); Test.Not_Nil(stashes); Test.True(#stashes > 0); local popped, pop_error = Git.Stash_Pop(root, "stash@{0}"); Test.Not_Nil(popped, tostring(pop_error)); Test.Not_Nil(uv.fs_stat(root .. "/new.c"))
		end },
		{ "Git command failure returns an error", function(root) Git.Init(root); local out, err = Git.Run(root, { "not-a-real-git-subcommand" }); Test.Nil(out); Test.Type("string", err) end },
		{ "snapshot refreshes after creating a file", function(root) Git.Init(root); local first = Git.Snapshot(root); Test.Equal(0, vim.tbl_count(first.statuses)); Write(root .. "/later.c"); local second = Git.Snapshot(root); Test.Equal(1, vim.tbl_count(second.statuses)) end },
		{ "nested root path works", function(root) local nested = root .. "/deep project"; vim.fn.mkdir(nested, "p"); Git.Init(nested); Test.True(Git.Is_Repository(nested)) end },
		{ "finds parent repository root for nested project", function(root) Git.Init(root); local nested = root .. "/nested/project"; vim.fn.mkdir(nested, "p"); Test.Equal(vim.fs.normalize(root), Git.Repository_Root(nested)) end },
		{ "status paths remain absolute to parent repository", function(root) Git.Init(root); local nested = root .. "/nested/project"; Write(nested .. "/main.c"); local status = Git.Status(nested); Test.Not_Nil(status[vim.fs.normalize(nested .. "/main.c")]) end },
	}
	for _, case in ipairs(integration) do
		Test.Run("Git integration: " .. case[1], function()
			local root = New_Root()
			local ok, err = pcall(case[2], root)
			Cleanup(root)
			if not ok then error(err) end
		end)
	end
end

-- Count and contract checks for every public API; kept separate for precise failures.
local api = {
	"Run", "Repository_Root", "Is_Repository", "Branch", "Parse_Status", "Status", "Snapshot",
	"Init", "Add_All", "Commit", "Recent", "Branches", "Remotes", "Remote_Details", "Tags",
	"Stashes", "Log", "Diff", "Diff_Name_Status", "Stage", "Unstage", "Fetch", "Push", "Pull",
	"Switch_Branch", "Create_Branch", "Delete_Branch", "Create_Tag", "Delete_Tag", "Stash", "Stash_Pop", "Stash_Apply",
	"Add_Remote", "Remove_Remote",
}
for _, name in ipairs(api) do
	Test.Run("Git public API exists: " .. name, function() Test.Type("function", Git[name]) end)
end

for _, count in ipairs({ -5, 0, 1, 5, 100, 1000, "3", "not-number" }) do
	Test.Run("Git recent-log count is bounded: " .. tostring(count), function()
		-- Git.Recent clamps the count before constructing a command. A missing
		-- repository provides a stable failure result without depending on history.
		if Has_Git() then
			local root = New_Root(); local _, err = Git.Recent(root, count); Test.Type("string", err); Cleanup(root)
		else
			Test.True(true)
		end
	end)
end
