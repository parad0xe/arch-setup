-- =============================================================
-- nvim-lint — run CLI linters (flake8, mypy, ...) and show the
-- result as Neovim diagnostics.
-- https://github.com/mfussenegger/nvim-lint
--
-- The python interpreter detection (venv/poetry) lives in
-- lua/config/python.lua and is shared with the LSP plugin.
-- =============================================================
return {
	"mfussenegger/nvim-lint",
	enabled = true,

	config = function()
		-- Note: the repo is "nvim-lint" but the Lua module is just "lint".
		local lint = require("lint")
		local get_python_path = require("config.python").get_python_path

		-- Register python linters, but only the tools actually
		-- installed on this machine.
		local python_linters = {}
		if vim.fn.executable("flake8") == 1 then
			table.insert(python_linters, "flake8")
		end
		if vim.fn.executable("mypy") == 1 then
			local mypy = lint.linters.mypy
			mypy.args = vim.list_extend(mypy.args or {}, {
				"--cache-dir=/dev/null", -- never write .mypy_cache
				"--python-executable", get_python_path(),
				"--strict",
			})
			table.insert(python_linters, "mypy")
		end
		if #python_linters > 0 then
			lint.linters_by_ft.python = python_linters
		end

		-- Re-run linters when a file changes, but only for
		-- filetypes that actually have linters configured.
		vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave", "BufReadPost", "BufNewFile" }, {
			callback = function(args)
				if lint.linters_by_ft[vim.bo[args.buf].filetype] then
					lint.try_lint()
				end
			end,
		})
	end,
}
