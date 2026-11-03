-- =============================================================
-- nvim-autopairs — auto-close brackets, quotes, etc.
-- Docs: :h nvim-autopairs  / https://github.com/windwp/nvim-autopairs
-- =============================================================
return {
	"windwp/nvim-autopairs",
	event = "InsertEnter", -- load only when you first enter insert mode

	-- `opts` is passed to require("nvim-autopairs").setup(opts)
	opts = {
		-- Don't create pairs in these filetypes (typing " to filter
		-- Telescope results should not insert a pair of quotes).
		disable_filetype = { "TelescopePrompt", "vim" },

		-- Wrap existing text fast: type the opening char, press <A-e>,
		-- pick the end point with the highlighted key, done.
		fast_wrap = {},

		-- Treesitter-aware pairing: don't insert a second quote when
		-- you're already INSIDE a string (needs the parsers from
		-- treesitter.lua, default rules cover lua/python/js/etc.).
		check_ts = true,
	},
}
