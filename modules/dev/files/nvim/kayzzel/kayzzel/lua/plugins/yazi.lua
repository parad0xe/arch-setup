-- =============================================================
-- yazi.nvim — Yazi file manager, embedded in Neovim.
-- https://github.com/mikavilpas/yazi.nvim
--
-- What the bridge adds over just running yazi in a terminal:
--   - hover a file in yazi, press q → the file opens in your
--     current Neovim buffer (the "oil-like" behavior)
--   - buffers open in Neovim are marked with * inside yazi
--   - rename/delete in yazi → open buffers follow along
-- =============================================================
return {
	"mikavilpas/yazi.nvim",

	keys = {
		{ "<leader>md", "<cmd>Yazi<cr>", desc = "Open yazi (current file)" },
	},

	opts = {
		-- Opening a DIRECTORY (nvim .) launches yazi too,
		-- replacing netrw entirely.
		open_for_directories = true,
	},
}
