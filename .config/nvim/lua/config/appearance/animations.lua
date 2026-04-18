
-- https://github.com/rachartier/tiny-glimmer.nvim
local tiny_glimmer_ok, tiny_glimmer = pcall(require, "tiny-glimmer")
if tiny_glimmer_ok then
    tiny_glimmer.setup()
end
