return {
	{
		dir = vim.fn.expand("~/Git/HyperMax/hypermax.nvim"),
		name = "hypermax.nvim",
		lazy = false,

		config = function()
			require("hypermax").setup({
				project_dir = "~/Code",
				create_missing_dir = true,
				open_after_create = false,
				default_language = "c",
			})
		end,
	},
}
