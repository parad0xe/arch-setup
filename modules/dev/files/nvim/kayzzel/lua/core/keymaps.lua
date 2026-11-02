-- Leader key
local keymap = vim.keymap.set

-- Normal
keymap("n", "<leader>w", "<CMD>w<CR>", {desc = "save file"})
keymap("n", "<leader>q", "<CMD>q<CR>", {desc = "quit vim"})
keymap("n", "<leader>Q", "<CMD>q!<CR>", {desc = "force quit vim"})
keymap("n", "<leader>x", "<CMD>x<CR>", {desc = "save quit vim"})

keymap("n", "<C-k>", "V:move '<-2<CR>gv-gv<ESCAPE>", { desc = "Déplace le texte vers le haut" })
keymap("n", "<C-j>", "V:move '>+1<CR>gv-gv<ESCAPE>", { desc = "Déplace le texte vers le bas"})
keymap("x", "<C-k>", ":move '<-2<CR>gv-gv", { desc = "Déplace le texte vers le haut" })
keymap("x", "<C-j>", ":move '>+1<CR>gv-gv", { desc = "Déplace le texte vers le bas"})

keymap("n", "<C-u>", "<C-u>zz", { desc = "Go up half a page and center the screen"})
keymap("n", "<C-d>", "<C-d>zz", { desc = "Go down half a page and center the screen"})

-- search terms stay centered
keymap("n", "n", "nzzzv")
keymap("n", "N", "Nzzzv")

-- keep visual selection after indenting (instead of losing it)
keymap("v", "<", "<gv")
keymap("v", ">", ">gv")

-- quick substitution of word under cursor across file
keymap("n", "<leader>r", ":%s/\\<<C-r><C-w>\\>/<C-r><C-w>/gI<Left><Left><Left>",
    { desc = "Replace word under cursor" })

-- open a scratch buffer
keymap("n", "<leader>bs", function()
    vim.cmd("enew")
    vim.bo.buftype = "nofile"
    vim.bo.bufhidden = "wipe"
    vim.notify("Scratch buffer opened", vim.log.levels.INFO)
end, { desc = "Open scratch buffer" })

-- close all other buffers
keymap("n", "<leader>bo", ":%bd|e#|bd#<CR>", { desc = "Close all other buffers" })

-- disable a plugin
vim.keymap.set("n", "<leader>pd", function()
    vim.ui.input({ prompt = "Disable plugin: " }, function(name)
        if not name or name == "" then return end
        require("lazy").disable(name)
        vim.notify("Plugin disabled: " .. name, vim.log.levels.INFO)
    end)
end, { desc = "Disable plugin temporarily" })

-- Lsp
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local opts = { buffer = ev.buf }
    vim.keymap.set("n", "gd",  vim.lsp.buf.definition,     opts)
    vim.keymap.set("n", "K",   vim.lsp.buf.hover,          opts)
    vim.keymap.set("n", "gi",  vim.lsp.buf.implementation, opts)
    vim.keymap.set("n", "grn", vim.lsp.buf.rename,         opts)
    vim.keymap.set("n", "gra", vim.lsp.buf.code_action,    opts)
    vim.keymap.set("n", "grr", vim.lsp.buf.references,     opts)
  end,
})


-- Undotree
keymap("n" , "<leader>ut", "<CMD>UndotreeToggle<CR>", {desc = "toggle undotree"})

-- Oil
keymap("n" , "<leader>md", "<CMD>Oil<CR>", {desc = "Start Oil"})

-- 42Header
keymap("n" , "<leader>h", "<CMD>Stdheader<CR>", {desc = "Insert 42 header"})

-- Custom folding keybind
keymap("n", "<leader>:", "zc", { desc = "Close Fold" })
keymap("n", "<leader>;", "za", { desc = "togle Fold" })

-- Telescope
--keymap("n", "<space>fr", require('telescope.builtin').lsp_references)
keymap("n", "<space>fb", require('telescope.builtin').buffers)
keymap("n", "<space><space>", require('telescope.builtin').find_files)
keymap("n", "<space>li", require("telescope.builtin").live_grep)
keymap("n", "<space>en", function()
	require('telescope.builtin').find_files {
		cwd = vim.fn.stdpath("config")
	}
	end
)

-- Search for the symbol under the cursor
vim.keymap.set("n", "<leader>gd", function()
  local word = vim.fn.expand("<cword>")
  require("telescope.builtin").live_grep({ default_text = word })
end, { desc = "Go to Definition (grep)" })

-- W3m
vim.keymap.set("n", "<leader>s", function()
  vim.ui.input({ prompt = "Search: " }, function(input)
    if not input or input == "" then return end
	vim.cmd("enew")
    local keys = vim.api.nvim_replace_termcodes(
      ":W3m " .. input .. "<CR>",
      true, false, true
    )
    vim.api.nvim_feedkeys(keys, "n", false)
  end)
end)

-- Markdown
keymap("n", "<space>m", "<cmd>MarkdownPreviewToggle<cr>", { desc = "Toggle markdown preview" })

-- Coller sans écraser le registre
keymap("v", "<leader>p", '"_dP')
