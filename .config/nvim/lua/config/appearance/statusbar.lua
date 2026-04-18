
-- https://github.com/tamton-aquib/staline.nvim
local staline_ok, staline = pcall(require, "staline")
if staline_ok then
    staline.setup({
        sections = {
            left = { '- ', '-mode', ' ', 'branch' },
            mid  = { },
            right = { 'file_name', 'cool_symbol', '-line_column' },
        },
    })
end
