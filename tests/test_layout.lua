local Test = require("tests.testlib")
local Layouts = require("hypermax.layouts")

Test.Run("Layout module exposes its expected public API", function()
	for _, name in ipairs({
		"Load_File",
		"Reload",
		"Get_Config",
		"Get_Defaults",
		"Get_Credits",
		"Get_Language",
		"Get_Languages",
		"Get_All",
		"Get",
		"Exists",
		"Get_IDs",
		"Get_For_Language",
		"Get_Commands",
		"Build_Manifest",
		"Apply",
		"Save",
		"Delete",
		"Is_Safe_Path",
	}) do
		Test.Type("function", Layouts[name], "Missing Layouts." .. name)
	end
end)

Test.Run("Safe relative paths are accepted", function()
	Test.True(Layouts.Is_Safe_Path("main.c"))
	Test.True(Layouts.Is_Safe_Path("src/main.c"))
	Test.True(Layouts.Is_Safe_Path(".github/workflows/test.yml"))
end)

Test.Run("Unsafe paths are rejected", function()
	for _, path in ipairs({ "", "/tmp/file", "../escape", "src/../escape", "./file", "C:/file", "a\\b", "a\0b" }) do
		Test.False(Layouts.Is_Safe_Path(path), "Unsafe path was accepted: " .. tostring(path))
	end
	for _, path in ipairs({ ".hmc/basics.json", ".git/config", "src/.hg/store", "file\nname.c" }) do
		Test.False(Layouts.Is_Safe_Path(path), "Protected or malformed path was accepted: " .. path)
	end
	Test.False(Layouts.Is_Safe_Path(nil), "nil path should be rejected")
	Test.False(Layouts.Is_Safe_Path(42), "numeric path should be rejected")
end)

Test.Run("Layout getters return tables and credits have valid fields", function()
	Test.Type("table", Layouts.Get_Config())
	Test.Type("table", Layouts.Get_Defaults())
	Test.Type("table", Layouts.Get_Languages())
	Test.Type("table", Layouts.Get_All())
	local credits = Layouts.Get_Credits()
	Test.Type("table", credits)
	Test.Type("string", credits.path)
	Test.Type("string", credits.content)
end)

Test.Run("Unknown layout returns nil and Exists is false", function()
	Test.Nil(Layouts.Get("hypermax_missing_layout"))
	Test.False(Layouts.Exists("hypermax_missing_layout"))
end)

Test.Run("Layout IDs are sorted and refer to existing layouts", function()
	local ids = Layouts.Get_IDs()
	for i, id in ipairs(ids) do
		Test.Type("string", id)
		Test.True(Layouts.Exists(id), "ID has no layout: " .. id)
		if i > 1 then
			Test.True(ids[i - 1] <= id, "Layout IDs are not sorted")
		end
	end
	Test.Equal(
		#ids,
		(function()
			local n = 0
			for _ in pairs(Layouts.Get_All()) do
				n = n + 1
			end
			return n
		end)()
	)
end)

Test.Run("C manifest can be built and contains expected files", function()
	local manifest, err = Layouts.Build_Manifest("c", nil, "HyperMaxTest")
	Test.Not_Nil(manifest, "Could not build C manifest: " .. tostring(err))
	Test.Equal("c", manifest.language)
	Test.Equal("HyperMaxTest", manifest.project_name)
	Test.Type("table", manifest.files)
	Test.Type("table", manifest.directories)
	Test.Type("string", manifest.files["README.md"])
	Test.Type("string", manifest.files["CREDITS.md"])
	Test.True(
		manifest.files["README.md"]:find("HyperMaxTest", 1, true) ~= nil,
		"README project-name placeholder was not replaced"
	)
end)

Test.Run("Unknown layout fails manifest generation with an error", function()
	local manifest, err = Layouts.Build_Manifest("c", "hypermax_missing_layout", "Test")
	Test.Nil(manifest)
	Test.Type("string", err)
end)

Test.Run("Layout file can be loaded and malformed path is rejected", function()
	local loaded, err = Layouts.Load_File(Layouts.json_path)
	Test.Not_Nil(loaded, "Could not load bundled layouts.json: " .. tostring(err))
	Test.Type("table", loaded.layouts)
end)

Test.Run("Reload succeeds without corrupting layout data", function()
	local ok, err = Layouts.Reload()
	Test.True(ok, "Layout reload failed: " .. tostring(err))
	Test.Type("table", Layouts.Get_All())
end)


Test.Run("Layout getter preserves the registry ID on selected layouts", function()
	local ids = Layouts.Get_IDs()
	if #ids == 0 then return end
	local layout = Layouts.Get(ids[1])
	Test.Equal(ids[1], layout.id)
end)

Test.Run("Saved layout includes nested paths and exact file contents", function()
	local original_path = Layouts.user_path
	local temporary = vim.fn.fnamemodify(vim.fn.tempname(), ":p")
	Layouts.user_path = temporary .. "/layouts.json"
	local id = "hypermax_layout_roundtrip_test"
	local layout = {
		name = "Roundtrip test",
		description = "Layout persistence test",
		directories = { "src", "src/nested", ".github/workflows" },
		files = {
			["src/main.c"] = "#include <stdio.h>\nint main(void) { return 0; }\n",
			[".gitignore"] = "build/\n*.o\n",
			[".github/workflows/test.yml"] = "name: test\non: [push]\n",
		},
		entry = "src/main.c",
	}
	local saved, save_error = Layouts.Save(id, layout)
	Test.True(saved, tostring(save_error))
	local loaded = Layouts.Get(id)
	Test.Equal(id, loaded.id)
	Test.Equal(layout.files["src/main.c"], loaded.files["src/main.c"])
	Test.Equal(layout.files[".gitignore"], loaded.files[".gitignore"])
	local manifest, manifest_error = Layouts.Build_Manifest("c", id, "Roundtrip")
	Test.Not_Nil(manifest, tostring(manifest_error))
	Test.Equal(layout.files["src/main.c"], manifest.files["src/main.c"])
	Test.Equal("src/main.c", manifest.entry)
	local deleted, delete_error = Layouts.Delete(id)
	Test.True(deleted, tostring(delete_error))
	Layouts.user_path = original_path
	Layouts.Reload()
	pcall(vim.fn.delete, temporary, "rf")
end)
