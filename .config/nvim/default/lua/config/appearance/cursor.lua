
-- https://github.com/sphamba/smear-cursor.nvim
local smear_cursor_ok, smear_cursor = pcall(require, "smear_cursor")
if smear_cursor_ok then
    smear_cursor.setup({
        enable = true
    })
end
