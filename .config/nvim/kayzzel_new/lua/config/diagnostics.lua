-- =============================================================
-- How diagnostics (from nvim-lint, LSP, ...) are DISPLAYED.
-- This configures the built-in vim.diagnostic system only.
-- =============================================================
vim.diagnostic.config({
	virtual_text = {
		prefix = "▎", -- marker before each inline diagnostic
	},
	signs = true, -- icons in the sign column
	underline = false, -- don't underline the offending text
	update_in_insert = false, -- don't jitter while typing
	severity_sort = true, -- most severe diagnostics first
})

-- Diagnostic colors (red for errors and warnings, as in the old config).
vim.api.nvim_set_hl(0, "DiagnosticError", { fg = "#ff5555" })
vim.api.nvim_set_hl(0, "DiagnosticWarn", { fg = "#ff5555" })
vim.api.nvim_set_hl(0, "DiagnosticVirtualTextError", { fg = "#ff6c6b" })
vim.api.nvim_set_hl(0, "DiagnosticVirtualTextWarn", { fg = "#ff6c6b" })
