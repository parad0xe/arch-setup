vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.opt.termguicolors = true

require('config.functions')
require('config.keymaps')

-- Navigation
require('config.navigation.nvim-tree')
require('config.navigation.telescope')

-- Code
require('config.code.package-manager')
require('config.code.treesitter')
require('config.code.lsp')
require('config.code.linters')
require('config.code.formatters')
require('config.code.goto-preview')
require('config.code.docstring')
require('config.code.completion')
require('config.code.norminette')
require('config.code.flash')

-- Appearance
require('config.appearance.theme')
require('config.appearance.cursor')
require('config.appearance.statusbar')
require('config.appearance.animations')

-- Tools
require('config.tools.terminal')
