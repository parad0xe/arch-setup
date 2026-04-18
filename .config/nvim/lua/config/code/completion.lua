
-- https://github.com/nvim-mini/mini.completion
local mini_ok, mini_completion = pcall(require, "mini.completion")
if mini_ok then
    mini_completion.setup()
end
