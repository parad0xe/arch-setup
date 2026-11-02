return {
	{
		"akinsho/toggleterm.nvim",
		version = "*",
		opts = {
			direction = "float",
		},
		config = function(_, opts)
			require("toggleterm").setup(opts)

			local Terminal = require("toggleterm.terminal").Terminal

			local term = Terminal:new({
				direction = "float",     -- float / horizontal / vertical
				close_on_exit = false,   -- IMPORTANT: do not destroy buffer on terminal exit
				hidden = true,           -- keep it hidden when toggled off
			})

			vim.keymap.set("n", "<leader>t", function()
				term:toggle()
			end, { desc = "Toggle persistent test terminal" })

			vim.keymap.set("t", "<C-t>", function()
				term:toggle()
			end, { desc = "Toggle persistent terminal in terminal mode", noremap = true })
			-- Temp directory
			local test_tmpdir = vim.fn.tempname()
			vim.fn.mkdir(test_tmpdir, "p")

			-- Persistent Terminal instance
			local test_term = Terminal:new({
				dir = test_tmpdir,
				direction = "float",
				close_on_exit = false,
			})

			-- Function to open test file in temp dir
			local function open_test_file(lang)
				local filepath = test_tmpdir .. "/test." .. lang
				vim.cmd("edit " .. vim.fn.fnameescape(filepath))
				vim.bo.filetype = lang
			end

			-- Leader mapping: <leader>e
			-- - If no arg => open terminal
			-- - If arg => open file only
			vim.keymap.set("n", "<leader>e", function()
				vim.ui.input({ prompt = "Open test file (e.g. py, c). Leave empty for terminal: " }, function(input)
					if not input or input == "" then
						-- open terminal
						test_term:toggle()
						return
					end

					-- open file only
					open_test_file(input)
				end)
			end, { desc = "Open test file or terminal" })
		end,
	},
}
