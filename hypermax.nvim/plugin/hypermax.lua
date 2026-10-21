-- Standard Neovim runtime entry point. Calling setup() again is safe and
-- allows a user configuration to override defaults before plugin loading.
if vim.g.loaded_hypermax then
	return
end
vim.g.loaded_hypermax = true

require("hypermax").setup()
