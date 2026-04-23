keymap("n", "<C-o>", ":CFormatter42<CR>", { desc = "Format C code (42)" })

-- https://github.com/stevearc/conform.nvim
local conform_ok, conform = pcall(require, "conform")
if conform_ok then
	conform.setup({
		formatters_by_ft = {
			python = { "ruff_organize_imports", "ruff_fix", "custom_ruff_format", "custom_yapf" },
		},

		formatters = {
			custom_ruff_format = {
				command = "ruff",
				args = {
					"format",
					"--line-length", "79",
					"--stdin-filename", "$FILENAME",
					"-",
				},
			},
			custom_yapf = {
				command = "yapf",
				args = {
					"--style",
					"{" ..
						"BASED_ON_STYLE: google," ..
						"COALESCE_BRACKETS: True," ..
						"COLUMN_LIMIT: 79," ..
						"DEDENT_CLOSING_BRACKETS: True," ..
						"INDENT_WIDTH: 4," ..
						"SPACES_BEFORE_COMMENT: 2," ..
						"SPACES_AROUND_POWER_OPERATOR: True," ..
						"SPLIT_ALL_COMMA_SEPARATED_VALUES: False," ..
						"SPLIT_ALL_TOP_LEVEL_COMMA_SEPARATED_VALUES: True," ..
						"SPLIT_BEFORE_DOT: True," ..
						"SPLIT_BEFORE_DICT_SET_GENERATOR: True," ..
						"SPLIT_BEFORE_EXPRESSION_AFTER_OPENING_PAREN: True," ..
						"SPLIT_BEFORE_FIRST_ARGUMENT: True," ..
						"SPLIT_COMPLEX_COMPREHENSION: True," ..
						"SPLIT_PENALTY_AFTER_OPENING_BRACKET: 10000000" ..
					"}",
					"$FILENAME"
				},
				stdin = false,
			},
		},

		format_on_save = {
			lsp_fallback = false,
			timeout_ms = 1000,
		},
	})

	keymap({ "n", "v" }, "<C-l>", function()
		conform.format({ async = true, lsp_fallback = false })
	end, { desc = "Format file (yapf + ruff)" })
end
