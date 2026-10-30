
-- https://github.com/mfussenegger/nvim-lint
-- Syntax + Types analysis
local lint_ok, lint = pcall(require, "lint")
if lint_ok then
    if vim.fn.executable("flake8") == 1 then
        lint.linters_by_ft.python = lint.linters_by_ft.python or {}
        table.insert(lint.linters_by_ft.python, "flake8")
    end

    if vim.fn.executable("mypy") == 1 then
        lint.linters_by_ft.python = lint.linters_by_ft.python or {}
        table.insert(lint.linters_by_ft.python, "mypy")

        local mypy = lint.linters.mypy
        mypy.args = vim.list_extend(mypy.args or {}, { 
            "--cache-dir=/dev/null",
            "--python-executable", get_python_path()
        })
    end

    vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave", "BufReadPost", "BufNewFile" }, {
		pattern = "*.py",
        callback = function()
            lint.try_lint()
        end,
    })
end

vim.diagnostic.config({
	virtual_text = {
		prefix = "●",
		severity_sort = true,
	},
	float = {
		border = "rounded",
		source = "always",
	},
	signs = true,
	underline = true,
	update_in_insert = false,
})

vim.api.nvim_set_hl(0, "DiagnosticError", { fg = "#ff5555" })
vim.api.nvim_set_hl(0, "DiagnosticWarn",  { fg = "#ff5555" })
-- vim.api.nvim_set_hl(0, "DiagnosticWarn",  { fg = "#f1fa8c" })

vim.api.nvim_set_hl(0, "DiagnosticVirtualTextError", { fg = "#ff6c6b" })
vim.api.nvim_set_hl(0, "DiagnosticVirtualTextWarn",  { fg = "#ff6c6b" })
--vim.api.nvim_set_hl(0, "DiagnosticVirtualTextWarn",  { fg = "#ECBE7B" })

keymap("n", "<C-p>", vim.diagnostic.open_float, { desc = "Open diagnostic float window" })
