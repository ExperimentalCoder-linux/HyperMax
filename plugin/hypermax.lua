-- Prevent this runtime script from loading twice.
if vim.g.loaded_hypermax then
	return
end

vim.g.loaded_hypermax = true

-- Initialise HyperMax and register its keymaps.
require("hypermax").setup()
