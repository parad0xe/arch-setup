
keymap("n", "<C-q>", function()
    vim.cmd("close")
    editor_focus()
end, { desc = "Smart close window" })

keymap("n", " lg", "<cmd>LazyGit<cr>", { desc = "Open lazygit window" })
keymap("n", " mt", "<cmd>MarkdownPreviewToggle<cr>", { desc = "Toggle markdown preview in browser" })
