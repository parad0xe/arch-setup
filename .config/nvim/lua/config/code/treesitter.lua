
-- https://github.com/nvim-treesitter/nvim-treesitter
local treesitter_ok, treesitter = pcall(require, "nvim-treesitter")
if treesitter_ok then
	treesitter.setup({
		install_dir = vim.fn.stdpath('data') .. '/site'
	})
	treesitter.install({ 'python' })
end
