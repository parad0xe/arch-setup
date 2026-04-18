-- https://github.com/folke/flash.nvim
local flash_ok, flash = pcall(require, "flash")
if flash_ok then
    flash.setup({})

    keymap({ "n", "x", "o" }, "ff", function() flash.jump() end, { desc = "Flash" })
    keymap({ "n", "x", "o" }, "FF", function() flash.treesitter() end, { desc = "Flash Treesitter" })
end
