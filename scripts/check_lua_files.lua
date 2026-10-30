-- Compile every plugin, test, and specification file with Neovim's own Lua runtime.
local directories = { "lua", "plugin", "tests", "spec", "scripts" }
local checked = 0

for _, directory in ipairs(directories) do
	local files = vim.fn.globpath(directory, "**/*.lua", false, true)
	for _, filename in ipairs(files) do
		local chunk, err = loadfile(filename)
		if not chunk then
			error(string.format("Lua syntax error in %s: %s", filename, tostring(err)), 0)
		end
		checked = checked + 1
	end
end

print(string.format("HyperMax: Neovim Lua parser accepted %d files", checked))
