return {
    {
        "williamboman/mason.nvim",
        opts = {},
    },
    {
        "williamboman/mason-lspconfig.nvim",
        dependencies = {
            "williamboman/mason.nvim",
            "saghen/blink.cmp",     -- needed to get capabilities
        },
        config = function()
            require("mason-lspconfig").setup({
                ensure_installed = { "lua_ls", "ts_ls", "pyright", "clangd", "rust_analyzer" },
            })

            local mason_bin = vim.fn.stdpath("data") .. "/mason/bin/"

            -- ── CAPABILITIES ───────────────────────────────────────────────────
            -- This is the critical piece for auto-import to work.
            -- blink.cmp enhances the default LSP capabilities to tell each
            -- server that this client supports:
            --   - additionalTextEdits (auto-imports)
            --   - resolveSupport (lazy-resolve full completion items)
            --   - snippetSupport (snippet completions)
            -- Without passing these, the LSP will never send import edits.
            local capabilities = require("blink.cmp").get_lsp_capabilities()

            -- ── LSP CONFIGS ────────────────────────────────────────────────────

            vim.lsp.config("lua_ls", {
                cmd          = { mason_bin .. "lua-language-server" },
                filetypes    = { "lua" },
                capabilities = capabilities,
                settings     = {
                    Lua = {
                        diagnostics = { globals = { "vim" } },
                        workspace   = { checkThirdParty = false },
                        telemetry   = { enable = false },
                    },
                },
            })

            vim.lsp.config("pyright", {
                cmd          = { mason_bin .. "pyright-langserver", "--stdio" },
                filetypes    = { "python" },
                capabilities = capabilities,
				on_init = function(client)
					client.config.settings.python.pythonPath = get_python_path()
				end,
                settings     = {
                    python = {
                        analysis = {
                            -- auto-import completions in pyright
                            autoImportCompletions = true,
                            typeCheckingMode      = "basic",
                        },
                    },
                },
            })

            vim.lsp.config("ts_ls", {
                cmd          = { mason_bin .. "typescript-language-server", "--stdio" },
                filetypes    = { "javascript", "typescript", "javascriptreact", "typescriptreact" },
                capabilities = capabilities,
                settings     = {
                    typescript = {
                        preferences = {
                            -- auto-import style for TypeScript
                            importModuleSpecifier = "relative",
                        },
                    },
                    javascript = {
                        preferences = {
                            importModuleSpecifier = "relative",
                        },
                    },
                },
            })

            vim.lsp.config("clangd", {
                cmd          = { mason_bin .. "clangd", "--background-index", "--clang-tidy" },
                filetypes    = { "c", "cpp", "objc", "objcpp" },
                capabilities = capabilities,
            })

            vim.lsp.config("rust_analyzer", {
                cmd          = { mason_bin .. "rust-analyzer" },
                filetypes    = { "rust" },
                capabilities = capabilities,
                settings     = {
                    ["rust-analyzer"] = {
                        imports = {
                            -- auto-import style for Rust
                            granularity = { group = "module" },
                            prefix      = "self",
                        },
                        cargo    = { allFeatures = true },
                        procMacro = { enable = true },
                    },
                },
            })

            vim.lsp.enable({ "lua_ls", "pyright", "ts_ls", "clangd", "rust_analyzer" })
        end,
    },
}
