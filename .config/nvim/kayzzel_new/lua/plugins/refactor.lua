-- =============================================================
-- refactoring.nvim (ThePrimeagen) — programmatic refactors:
-- extract function/variable, inline them, plus debug prints.
-- Treesitter-driven: needs a parser for the language
-- (see treesitter.lua); works on visual selections, and in
-- normal mode asks for a textobject (e.g. `<leader>re iw`).
--
-- API note (2025 rewrite): the old string API —
--   require("refactoring").refactor("Extract Function")
-- — no longer exists; the plugin now exports dedicated
-- functions (extract_func(), extract_var(), ...). Same for
-- debug: printf() became print_var/print_exp/print_loc.
-- `extract_block` was removed upstream, so the old <leader>rb /
-- <leader>rB binds have no replacement.
-- =============================================================
return {
	"ThePrimeagen/refactoring.nvim",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"lewis6991/async.nvim", -- required: provides the async() module
	},

	keys = {
		-- ── Refactorings ───────────────────────────────────────
		-- expr = true is required: the function RETURNS a key
		-- sequence (in normal mode, the textobject to capture).
		{
			"<leader>re",
			mode = { "n", "x" },
			function()
				return require("refactoring").extract_func()
			end,
			expr = true,
			desc = "Refactor: extract function",
		},
		{
			"<leader>ree",
			mode = { "n" },
			function()
				return require("refactoring").extract_func() .. "_"
			end,
			expr = true,
			desc = "Refactor: extract function (line)",
		},
		{
			"<leader>rE",
			mode = { "n", "x" },
			function()
				return require("refactoring").extract_func_to_file()
			end,
			expr = true,
			desc = "Refactor: extract function to file",
		},
		{
			"<leader>rv",
			mode = { "n", "x" },
			function()
				return require("refactoring").extract_var()
			end,
			expr = true,
			desc = "Refactor: extract variable",
		},
		{
			"<leader>rvv",
			mode = { "n" },
			function()
				return require("refactoring").extract_var() .. "_"
			end,
			expr = true,
			desc = "Refactor: extract variable (line)",
		},
		{
			"<leader>ri",
			mode = { "n", "x" },
			function()
				return require("refactoring").inline_var()
			end,
			expr = true,
			desc = "Refactor: inline variable",
		},
		{
			"<leader>rI",
			mode = { "n", "x" },
			function()
				return require("refactoring").inline_func()
			end,
			expr = true,
			desc = "Refactor: inline function",
		},

		-- ── Picker ─────────────────────────────────────────────
		{
			"<leader>rr",
			mode = { "n", "x" },
			function()
				require("refactoring").select_refactor()
			end,
			desc = "Refactor: pick from list",
		},

		-- ── Debug prints ───────────────────────────────────────
		-- print_var inserts a print of the var under cursor (n:
		-- appends "iw" to capture the word); cleanup removes all
		-- debug prints it inserted (marked in comments).
		{
			"<leader>rd",
			mode = { "x", "n" },
			function()
				return require("refactoring.debug").print_var({ output_location = "below" })
					.. "iw"
			end,
			expr = true,
			desc = "Debug: print var below",
		},
		{
			"<leader>rp",
			mode = { "x", "n" },
			function()
				return require("refactoring.debug").print_var({ output_location = "above" })
					.. "iw"
			end,
			expr = true,
			desc = "Debug: print var above",
		},
		{
			"<leader>rc",
			mode = { "n" },
			function()
				require("refactoring.debug").cleanup({})
			end,
			desc = "Debug: cleanup prints",
		},
	},

	opts = {
		show_success_message = true, -- notify after each refactoring
	},
}
