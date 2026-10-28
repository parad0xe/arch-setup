-- =============================================================
-- toggleterm — persistent floating terminals.
-- https://github.com/akinsho/toggleterm.nvim
--
-- Keymap scheme: the <leader>t prefix is shared with the tab
-- bindings — tt opens the terminal, tn/to/tc/tm manage tabs.
-- <C-t> closes it from inside terminal mode.
-- =============================================================
return {
	"akinsho/toggleterm.nvim",
	version = "*",

	keys = {
		-- Load on first toggle attempt.
		{ "<leader>tt", desc = "Toggle terminal" },
	},

	config = function()
		require("toggleterm").setup({
			direction = "float", -- floating window; also: horizontal / vertical
		})

		local Terminal = require("toggleterm.terminal").Terminal

		-- The main persistent terminal: state survives being hidden
		-- (a running process keeps running when you toggle it away).
		local term = Terminal:new({
			direction = "float",
			close_on_exit = false, -- don't destroy the buffer when the shell exits
			hidden = true, -- start hidden, created on first toggle
		})

		vim.keymap.set("n", "<leader>tt", function()
			term:toggle()
		end, { desc = "Toggle persistent terminal" })

		-- Also closable from inside terminal mode.
		vim.keymap.set("t", "<C-t>", function()
			term:toggle()
		end, { desc = "Toggle persistent terminal (terminal mode)", noremap = true })
	end,
}
