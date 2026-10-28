-- =============================================================
-- Rose Pine colorscheme.
-- https://rosepinetheme.com — variants: "main", "moon", "dawn"
-- =============================================================
return {
	"rose-pine/neovim",
	name = "rose-pine",

	-- Load at startup, before any other plugin, so nothing flashes
	-- in the wrong colors first.
	lazy = false,
	priority = 1000,

	config = function()
		require("rose-pine").setup({
			-- variant = "main", -- default; alternatives: "moon", "dawn"
			disable_background = true, -- transparent background (matches the terminal)
			disable_float_background = true, -- transparent floating windows too
		})

		-- Apply the colorscheme.
		vim.cmd("colorscheme rose-pine")
	end,
}
