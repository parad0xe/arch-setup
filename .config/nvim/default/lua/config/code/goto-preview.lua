
-- https://github.com/rmagatti/goto-preview
local goto_preview_ok, goto_preview = pcall(require, "goto-preview")
if goto_preview_ok then
    goto_preview.setup({})

	keymap("n", "<C-f>", function()
		goto_preview.goto_preview_definition()
	end, { desc = "Open preview window of the definition" })

	keymap("n", "<A-f>", function()
		goto_preview.close_all_win()
		editor_focus()
	end, { desc = "Close all opened preview windows" })
end
