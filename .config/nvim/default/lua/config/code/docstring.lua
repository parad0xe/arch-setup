
-- https://github.com/kkoomen/vim-doge
if vim.fn.exists(':DogeGenerate') then
	vim.api.nvim_create_user_command('DogeAll', function()
	  vim.cmd([[g/^\s*\(def\s\+\k\+\s*(\|class\s\+\k\+\)/DogeGenerate google]])
	  vim.cmd([[ %s/\("""\)\[TODO:summary\]\n\(\s*\)/\1\2/g ]])
	  vim.cmd([[ %s/\[TODO:description\]/\[TODO:brief_description\]/g ]])
	end, {})

	keymap('n', ' x', '<Plug>(doge-generate)', { desc = "Generate Docstring for current cursor position" })
end

-- https://github.com/camAtGitHub/pydochide.nvim
-- if vim.fn.exists(':PyDocHide') == 1 then
-- 	vim.cmd('autocmd FileType python PyDocHide')
-- end
