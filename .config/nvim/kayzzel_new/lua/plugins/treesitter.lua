-- =============================================================
-- nvim-treesitter (main branch) — real-syntax parsing, used for
-- highlighting, indentation and (later) smarter motions.
--
-- NOTE on the branch: treesitter was rewritten in 2025. On the
-- `main` branch there are NO `highlight = {enable=...}`-style
-- options anymore (those belong to the old `master` branch and
-- are silently ignored here). Instead:
--   - parsers are installed with require("nvim-treesitter").install()
--   - highlighting comes from Neovim's built-in vim.treesitter.start()
--   - indentation is opt-in via indentexpr
-- =============================================================
return {
	"nvim-treesitter/nvim-treesitter",
	branch = "main",
	lazy = false, -- needed before files are displayed
	build = ":TSUpdate", -- update parsers with :TSUpdate
	cmd = { "TSUpdate", "TSInstall", "TSUninstall" },

	config = function()
		local parsers = {
			"bash", "c", "cpp", "diff",
			"html", "javascript", "jsdoc", "json", "jsonc",
			"lua", "luadoc", "luap",
			"make", "markdown", "markdown_inline",
			"printf", "python", "query", "regex",
			"toml", "tsx", "typescript",
			"vim", "vimdoc", "xml", "yaml",
		}

		-- Installs missing parsers, updates existing ones (async).
		require("nvim-treesitter").install(parsers)

		-- For every buffer whose filetype HAS a parser installed:
		-- turn on treesitter highlighting (built into Neovim) and
		-- treesitter-based indentation (experimental, but good
		-- in practice). Buffers without a parser keep the default.
		vim.api.nvim_create_autocmd("FileType", {
			callback = function(args)
				local ok = pcall(vim.treesitter.start, args.buf)
				if ok then
					vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
				end
			end,
		})
	end,
}
