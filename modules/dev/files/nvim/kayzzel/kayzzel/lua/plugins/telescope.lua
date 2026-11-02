-- =============================================================
-- Telescope — fuzzy finder: files, live grep, buffers, config.
-- https://github.com/nvim-telescope/telescope.nvim
--
-- The fzf-native extension is a compiled C sorter: much faster
-- results ranking than the pure-Lua one.
-- =============================================================
return {
	{
		"nvim-telescope/telescope.nvim",
		tag = "v0.2.0", -- pin the release; the plugin is stable
		dependencies = {
			"nvim-lua/plenary.nvim", -- telescope's helper library
			{ "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
		},

		-- Load only when one of these keys is pressed.
		keys = {
			{ "<leader><leader>", "<cmd>Telescope find_files<cr>", desc = "Find files" },
			{ "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Find buffers" },
			{ "<leader>li", "<cmd>Telescope live_grep<cr>", desc = "Live grep (search in files)" },
			{
				"<leader>en",
				function()
					require("telescope.builtin").find_files({
						cwd = vim.fn.stdpath("config"), -- search inside the nvim config
					})
				end,
				desc = "Find files in nvim config",
			},
			{
				"<leader>gd",
				function()
					-- Pre-fill live_grep with the word under the cursor.
					require("telescope.builtin").live_grep({
						default_text = vim.fn.expand("<cword>"),
					})
				end,
				desc = "Grep word under cursor",
			},

			-- LSP symbols & diagnostics
			{ "<leader>ds", "<cmd>Telescope lsp_document_symbols<cr>", desc = "Document symbols" },
			{ "<leader>ws", "<cmd>Telescope lsp_workspace_symbols<cr>", desc = "Workspace symbols" },
			{ "<leader>dg", "<cmd>Telescope diagnostics<cr>", desc = "Diagnostics (all buffers)" },

			-- "What am I mapped to?" — search every keymap (incl. its desc)
			{ "<leader>mp", "<cmd>Telescope keymaps<cr>", desc = "Search keymaps" },

			-- Git pickers (builtin; work in any git repo)
			{ "<leader>gc", "<cmd>Telescope git_commits<cr>", desc = "Git commits (repo)" },
			{ "<leader>gb", "<cmd>Telescope git_branches<cr>", desc = "Git branches (checkout <CR>)" },
			{ "<leader>gs", "<cmd>Telescope git_status<cr>", desc = "Git status (changed files)" },
		},

		config = function()
			local actions = require("telescope.actions")

			require("telescope").setup({
				defaults = {
					prompt_prefix = "🔍 ",
					selection_caret = "➤ ",
					entry_prefix = "  ",
					initial_mode = "insert", -- start typing your query right away
					selection_strategy = "reset",
					sorting_strategy = "ascending", -- best matches on top
					layout_strategy = "horizontal",
					layout_config = {
						horizontal = {
							prompt_position = "top", -- type at the top, like fzf
							preview_width = 0.55,
							results_width = 0.8,
						},
						width = 0.87,
						height = 0.80,
						preview_cutoff = 120, -- below this width, hide the preview
					},
					file_ignore_patterns = { "node_modules", "%.git/" },
					path_display = { "truncate" }, -- shorten long paths in results

					mappings = {
						i = {
							["<Esc>"] = actions.close, -- close immediately
							["<C-j>"] = actions.move_selection_next,
							["<C-k>"] = actions.move_selection_previous,
							-- Send all results to the quickfix list and open it
							["<C-q>"] = actions.smart_send_to_qflist + actions.open_qflist,
						},
						n = {
							["q"] = actions.close,
							["j"] = actions.move_selection_next,
							["k"] = actions.move_selection_previous,
						},
					},
				},
				extensions = {
					fzf = {
						fuzzy = true,
						override_generic_sorter = true,
						override_file_sorter = true,
						case_mode = "smart_case",
					},
				},
			})

			require("telescope").load_extension("fzf")
		end,
	},
}
