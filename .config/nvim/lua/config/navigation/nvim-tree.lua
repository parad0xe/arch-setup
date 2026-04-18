
-- https://github.com/nvim-tree/nvim-tree.lua

local nvim_tree_ok, nvim_tree = pcall(require, "nvim-tree")
if nvim_tree_ok then
    local function my_on_attach(bufnr)
        local api = require("nvim-tree.api")
        local function opts(desc)
            return { desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
        end

        api.config.mappings.default_on_attach(bufnr)

        keymap('n', '<C-=>', api.tree.collapse_all, opts("Collapse All"))
    end

    nvim_tree.setup({
        on_attach = my_on_attach,
        sort = { sorter = "case_sensitive" },
        view = { width = 30 },
        update_focused_file = { enable = true },
        renderer = {
            group_empty = false,
            root_folder_label = false,
            icons = { web_devicons = { folder = { enable = true } } }
        },
        filters = { dotfiles = false },
    })

	keymap("n", " e", ":NvimTreeToggle<cr>", { desc = "Toggle explorer" })
	keymap("n", " f", ":NvimTreeFocus<cr>", { desc = "Focus explorer" })
	keymap("n", " R", ":NvimTreeRefresh<cr>", { desc = "Refresh explorer" })
	keymap("n", " 1", ":NvimTreeResize 50<cr>", { desc = "Resize explorer large" })
	keymap("n", " 0", ":NvimTreeResize 30<cr>", { desc = "Resize explorer default" })
end
