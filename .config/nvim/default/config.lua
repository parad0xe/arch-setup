vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.opt.termguicolors = true

require('config.functions')
require('config.options')
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

local diagnostics_active = true

vim.api.nvim_create_user_command('ToggleDiag', function()
    diagnostics_active = not diagnostics_active
    if diagnostics_active then
        vim.diagnostic.enable(true)
        print("Diagnostics activés")
    else
        vim.diagnostic.enable(false)
        print("Diagnostics désactivés")
    end
end, { desc = "Active ou désactive l'affichage des erreurs" })
keymap('n', " [[", "<cmd>ToggleDiag<cr>")
