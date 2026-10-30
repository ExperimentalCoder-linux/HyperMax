-- Small, automatically loaded runtime entry point. Delay initialization until
-- plugin-manager configuration callbacks have applied user preferences.
-- The scheduled marker prevents duplicate runtime loading; the public loaded
-- marker is set only after initialization succeeds.
if vim.g.loaded_hypermax or vim.g.hypermax_initialization_scheduled then
	return
end

vim.g.hypermax_initialization_scheduled = true

vim.schedule(function()
	vim.g.hypermax_initialization_scheduled = nil

	local ok, HyperMax = pcall(require, "hypermax")
	if not ok then
		vim.notify("HyperMax: could not load public module: " .. tostring(HyperMax), vim.log.levels.ERROR)
		return
	end

	local initialized, initialize_error = pcall(HyperMax.initialize)
	if not initialized then
		vim.notify("HyperMax: initialization failed: " .. tostring(initialize_error), vim.log.levels.ERROR)
		return
	end

	vim.g.loaded_hypermax = true
end)
