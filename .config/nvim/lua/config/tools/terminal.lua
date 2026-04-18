
-- https://github.com/akinsho/toggleterm.nvim
local toggleterm_ok, toggleterm = pcall(require, "toggleterm")
if toggleterm_ok then
    toggleterm.setup({
        size = function(term)
            local lines = vim.o.lines
            local height = math.floor(lines * 0.25)
            if height < 8 then height = 8 end
            if height > 20 then height = 20 end
            return height
        end,
        direction = "horizontal",
        persist_size = true,
        persist_mode = false,
        start_in_insert = true,
        close_on_exit = true,
		hide_numbers = true,
		shade_filetypes = {},
		shade_terminals = false,
    })

	-- open terminal
	keymap("n", "<C-t>", ":ToggleTerm<CR>", { desc = "Open terminal" })

	-- close terminal
	keymap("t", "<C-t>", function()
	  vim.cmd("stopinsert")
	  vim.cmd("ToggleTerm")
	  editor_focus()
	end, { desc = "Close terminal" })

	-- toggle focus
	local function smart_terminal_focus()
		if vim.bo.buftype == 'terminal' then
			vim.cmd("wincmd p")
		else
			for _, win in ipairs(vim.api.nvim_list_wins()) do
				local buf = vim.api.nvim_win_get_buf(win)
				if vim.bo[buf].buftype == 'terminal' then
					vim.api.nvim_set_current_win(win)
					vim.cmd("startinsert")
					return
				end
			end
			vim.cmd("ToggleTerm")
		end
	end
	keymap({'n', 't'}, '<C-LEFT>', smart_terminal_focus, { desc = "Toggle Focus Terminal/Editor" })
	keymap({'n', 't'}, '<C-RIGHT>', smart_terminal_focus, { desc = "Toggle Focus Terminal/Editor" })

	-- switch mode: normal -> terminal
	keymap("n", "<C-n>", "i", { desc = "Switch from normal to terminal mode" })

	-- switch mode: terminal -> normal
	keymap("t", "<C-n>", "<C-\\><C-n>", { desc = "Swtich from terminal to normal mode" })

	-- resize
	keymap("t", "<C-Up>", "<Cmd>resize +2<CR>", { desc = "Increase size of the terminal view" })
	keymap("t", "<C-Down>", "<Cmd>resize -2<CR>", { desc = "Decrease size of the terminal view" })
end
