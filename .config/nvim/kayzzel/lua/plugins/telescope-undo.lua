-- =============================================================
-- telescope-undo — browse undo history as a searchable tree with
-- diffs in the preview. Replaces the standalone undotree plugin
-- from the old config: the whole history is inside telescope.
-- https://github.com/debugloop/telescope-undo.nvim
-- =============================================================
return {
	"debugloop/telescope-undo.nvim",
	dependencies = { "nvim-telescope/telescope.nvim" },

	keys = {
		-- <CR> on an entry restores that state ("time travel").
		{ "<leader>ut", "<cmd>Telescope undo<cr>", desc = "Undo history" },
	},

	config = function()
		require("telescope").load_extension("undo")
	end,
}
