
-- https://github.com/nvim-telescope/telescope.nvim
local telescope_ok, telescope_builtin = pcall(require, 'telescope.builtin')
if telescope_ok then
    keymap('n', ' ff', telescope_builtin.find_files, { desc = 'Telescope find files' })
    keymap('n', ' fg', telescope_builtin.live_grep, { desc = 'Telescope live grep' })
    keymap('n', ' fb', telescope_builtin.buffers, { desc = 'Telescope buffers' })
    keymap('n', ' fh', telescope_builtin.help_tags, { desc = 'Telescope help tags' })
end
