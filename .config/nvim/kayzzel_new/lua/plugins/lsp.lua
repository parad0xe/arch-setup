-- =============================================================
-- LSP setup: language servers give you hover docs, go-to-
-- definition, rename, code actions, and completion data.
--
-- The three pieces:
--   mason.nvim       → installs server binaries into ~/.local/share/nvim/mason/
--   nvim-lspconfig   → ships the default config (cmd, filetypes, root dir) per server
--   vim.lsp.config/enable (Neovim 0.11+ API) → enables servers + your overrides
--
-- The blink.cmp plugin provides `get_lsp_capabilities()` which
-- tells servers what completions features we support (snippets,
-- resolve, auto-imports). blink.cmp is loaded from its own file.
-- =============================================================

return {
	{
		"williamboman/mason.nvim",
		opts = {},
		config = function(_, opts)
			require("mason").setup(opts)

			-- Auto-install missing servers. (mason.nvim itself has no
			-- ensure_installed option — that lived in the now-deprecated
			-- mason-lspconfig — so we do it explicitly: refresh the
			-- package registry, then install anything not present.)
			local servers = {
				"lua-language-server", -- → server "lua_ls"
				"pyright", -- → server "pyright"
				"typescript-language-server", -- → server "ts_ls"
				"clangd", -- → server "clangd"
				"rust-analyzer", -- → server "rust_analyzer"
			}

			local registry = require("mason-registry")
			registry.refresh(function()
				for _, name in ipairs(servers) do
					local pkg = registry.get_package(name)
					if not pkg:is_installed() then
						pkg:install()
					end
				end
			end)
		end,
	},

	{
		"neovim/nvim-lspconfig",
		dependencies = { "williamboman/mason.nvim", "saghen/blink.cmp" },
		config = function()
			local capabilities = require("blink.cmp").get_lsp_capabilities()
			local get_python_path = require("config.python").get_python_path

			-- ── Per-server settings ────────────────────────────────
			-- vim.lsp.config(<name>, {...}) overrides the defaults
			-- shipped by nvim-lspconfig; `capabilities` is the part
			-- that lets blink.cmp complete from this server.

			vim.lsp.config("lua_ls", {
				capabilities = capabilities,
				settings = {
					Lua = {
						-- `vim` is a global in config files; without this
						-- lua_ls flags every `vim.xxx` as undefined.
						diagnostics = { globals = { "vim" } },
						workspace = { checkThirdParty = false },
						telemetry = { enable = false },
					},
				},
			})

			vim.lsp.config("pyright", {
				capabilities = capabilities,
				on_init = function(client)
					-- Point pyright at the project venv (same detection mypy uses).
					client.config.settings.python.pythonPath = get_python_path()
				end,
				settings = {
					python = {
						analysis = {
							autoImportCompletions = true,
							typeCheckingMode = "basic",
						},
					},
				},
			})

			vim.lsp.config("ts_ls", {
				capabilities = capabilities,
				settings = {
					typescript = { preferences = { importModuleSpecifier = "relative" } },
					javascript = { preferences = { importModuleSpecifier = "relative" } },
				},
			})

			vim.lsp.config("clangd", {
				capabilities = capabilities,
				-- Background index = jump-to-def works across files
				-- without opening them first; clang-tidy = extra checks.
				cmd = { "clangd", "--background-index", "--clang-tidy" },
			})

			vim.lsp.config("rust_analyzer", {
				capabilities = capabilities,
				settings = {
					["rust-analyzer"] = {
						imports = {
							granularity = { group = "module" },
							prefix = "self",
						},
						cargo = { allFeatures = true },
						procMacro = { enable = true },
					},
				},
			})

			-- Enable the servers on their filetypes (from the nvim-
			-- lspconfig defaults; the cmds are found via mason's PATH).
			vim.lsp.enable({ "lua_ls", "pyright", "ts_ls", "clangd", "rust_analyzer" })

			-- ── LSP keymaps ───────────────────────────────────────
			-- Set only when a server actually attaches to the buffer,
			-- so they exist only where they do something.
			vim.api.nvim_create_autocmd("LspAttach", {
				callback = function(ev)
					local map = function(lhs, rhs, desc)
						vim.keymap.set("n", lhs, rhs, { buffer = ev.buf, desc = desc })
					end

					map("gd", vim.lsp.buf.definition, "Go to definition")
					map("gi", vim.lsp.buf.implementation, "Go to implementation")
					map("K", vim.lsp.buf.hover, "Show documentation")
					map("grn", vim.lsp.buf.rename, "Rename symbol")
					map("gra", vim.lsp.buf.code_action, "Code action")
					map("grr", vim.lsp.buf.references, "List references")
				end,
			})
		end,
	},
}
