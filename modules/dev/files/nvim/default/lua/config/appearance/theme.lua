
-- https://github.com/folke/tokyonight.nvim
local tokyonight_ok, tokyonight = pcall(require, "tokyonight")
if tokyonight_ok then
    tokyonight.setup({
		transparent = true,
		style = "moon",
	})
	vim.cmd("colorscheme tokyonight")
end

-- https://github.com/projekt0n/github-nvim-theme
local githubtheme_ok, githubtheme = pcall(require, "github-theme")
if githubtheme_ok then
    githubtheme.setup({
		options = {
			transparent = true,
		}
	})
	vim.cmd("colorscheme github_light")
end

-- https://github.com/xiyaowong/transparent.nvim
local transparent_ok, transparent = pcall(require, "transparent")
if transparent_ok then
    transparent.setup({
        groups = {
            'Normal', 'NormalNC', 'Comment', 'Constant', 'Special', 'Identifier',
            'Statement', 'PreProc', 'Type', 'Underlined', 'Todo', 'String', 'Function',
            'Conditional', 'Repeat', 'Operator', 'Structure', 'LineNr', 'NonText',
            'SignColumn', 'CursorLine', 'CursorLineNr', 'StatusLine', 'StatusLineNC',
            'EndOfBuffer',
        },
        extra_groups = {
            "NormalFloat", "NvimTreeNormal", "NvimTreeNormalNC", "NvimTreeNormalFloat",
            "NvimTreeEndOfBuffer", "StatusLine", "StatusLineNC", "BufferLineTabClose",
            "BufferlineBufferSelected", "BufferLineFill", "BufferLineBackground",
            "BufferLineSeparator", "BufferLineIndicatorSelected", "IndentBlanklineChar",
            "ToggleTerm", "LspFloatWinNormal", "Normal", "FloatBorder", "TermNormal",
            "TelescopeNormal", "TelescopeBorder", "TelescopePromptBorder",
        }
    })

	vim.api.nvim_set_hl(0, "NvimTreeWinSeparator", {
	  fg = "#352d36",
	  bg = "NONE"
	})

	vim.api.nvim_set_hl(0, "ColorColumn", {
	  bg = "#3b1414"
	})

	keymap("n", " tt", "<cmd>TransparentToggle<cr>", { desc = "Toogle Nvim Transparency" })
end
