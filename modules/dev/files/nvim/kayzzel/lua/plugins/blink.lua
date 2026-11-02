return {
    "saghen/blink.cmp",
    version = "*",
    dependencies = {
        -- snippet collection (blink uses it for the snippets source)
        "rafamadriz/friendly-snippets",
    },
    opts = {
        -- ── Keymaps ─────────────────────────────────────────────────────────
        keymap = {
            preset  = "default",
            ["<Tab>"] = { "accept", "fallback" }, -- Tab confirms
            ["<CR>"]  = { "fallback" },           -- Enter always = newline, never confirms
            -- <C-space>     → open / refresh completion menu
            -- <C-x> / <C-p> → next / previous item
            -- <C-e>         → close menu
            ["<C-x>"] = { "select_next", "fallback" },
            ["<C-p>"] = { "select_prev", "fallback" },
        },

        -- ── Appearance ───────────────────────────────────────────────────────
        appearance = {
            nerd_font_variant = "mono",
            -- show a kind icon + label next to each completion item
            kind_icons = {
                Text          = "󰉿",
                Method        = "󰆧",
                Function      = "󰊕",
                Constructor   = "",
                Field         = "󰜢",
                Variable      = "󰀫",
                Class         = "󰠱",
                Interface     = "",
                Module        = "",
                Property      = "󰜢",
                Unit          = "󰑭",
                Value         = "󰎠",
                Enum          = "",
                Keyword       = "󰌋",
                Snippet       = "",
                Color         = "󰏘",
                File          = "󰈙",
                Reference     = "󰈇",
                Folder        = "󰉋",
                EnumMember    = "",
                Constant      = "󰏿",
                Struct        = "󰙅",
                Event         = "",
                Operator      = "󰆕",
                TypeParameter = "",
            },
        },

        -- ── Sources ──────────────────────────────────────────────────────────
        sources = {
            default = { "lsp", "path", "snippets", "buffer" },
        },

        -- ── Completion ───────────────────────────────────────────────────────
        completion = {
            -- Trigger: show menu as soon as you start typing
            trigger = {
                show_on_insert_enter    = true,
                show_on_trigger_character = true,
            },

            -- List: how items are sorted and filtered
            list = {
                selection = {
                    preselect   = true,  -- first item is always highlighted
                    auto_insert = false,
                },
            },

            -- Menu appearance
            menu = {
                border      = "rounded",
                winhighlight = "Normal:BlinkCmpMenu,FloatBorder:BlinkCmpMenuBorder,CursorLine:BlinkCmpMenuSelection",
                draw = {
                    -- Show: icon  label  kind  source
                    columns = {
                        { "kind_icon", gap = 1 },
                        { "label", "label_description", gap = 1 },
                        { "kind", gap = 1 },
                        { "source_name" },
                    },
                },
            },

            -- Documentation popup
            documentation = {
                auto_show          = true,
                auto_show_delay_ms = 200,
                window = { border = "rounded" },
            },

            -- ── AUTO-IMPORT ──────────────────────────────────────────────────
            -- This is the key setting for auto-import:
            -- When you confirm a completion, blink will ask the LSP to resolve
            -- the full item including any additional text edits (imports, etc.)
            -- and apply them all at once.
            accept = {
                auto_brackets = { enabled = true },

                -- Resolve the completion item before inserting so that
                -- LSP-side additional edits (auto-imports) are applied.
                -- Works with ts_ls, pyright, rust_analyzer, clangd.
                on_accept = function(item)
                    -- blink v1 API: item.source resolves additional text edits
                    if item and item.source then
                        local client = item.source:get_lsp_client()
                        if client then
                            client.resolve_completion(item, function(resolved)
                                if resolved and resolved.additionalTextEdits then
                                    vim.lsp.util.apply_text_edits(
                                        resolved.additionalTextEdits,
                                        vim.api.nvim_get_current_buf(),
                                        client.offset_encoding
                                    )
                                end
                            end)
                        end
                    end
                end,
            },
        },

        -- ── Signature help ───────────────────────────────────────────────────
        -- Shows function signature (argument names + types) while you type
        signature = {
            enabled = true,
            window  = { border = "rounded" },
        },
    },

    -- ── LSP capabilities ─────────────────────────────────────────────────────
    -- This is the OTHER half of auto-import:
    -- blink must advertise to the LSP that the client supports
    -- additionalTextEdits and resolveSupport, otherwise the LSP
    -- won't send import information at all.
    config = function(_, opts)
        local blink = require("blink.cmp")
        blink.setup(opts)

        -- ── Theme ─────────────────────────────────────────────────────────────
        -- Colors matched to your rose-pine + purple noice theme
        local hl = vim.api.nvim_set_hl

        -- Menu windows
        hl(0, "BlinkCmpMenu",          { bg = "#1a1a2e" })
        hl(0, "BlinkCmpMenuBorder",    { fg = "#8024ca", bg = "NONE" })
        hl(0, "BlinkCmpMenuSelection", { bg = "#6c4791" })

        -- Documentation popup
        hl(0, "BlinkCmpDoc",           { bg = "#1a1a2e" })
        hl(0, "BlinkCmpDocBorder",     { fg = "#8024ca", bg = "NONE" })

        -- Signature help
        hl(0, "BlinkCmpSignatureHelp",       { bg = "#1a1a2e" })
        hl(0, "BlinkCmpSignatureHelpBorder", { fg = "#8024ca", bg = "NONE" })

        -- Kind icon colors per completion type
        hl(0, "BlinkCmpKindFunction",    { fg = "#ff79c6" })
        hl(0, "BlinkCmpKindMethod",      { fg = "#ff79c6" })
        hl(0, "BlinkCmpKindConstructor", { fg = "#ff79c6" })
        hl(0, "BlinkCmpKindVariable",    { fg = "#bd93f9" })
        hl(0, "BlinkCmpKindField",       { fg = "#bd93f9" })
        hl(0, "BlinkCmpKindProperty",    { fg = "#bd93f9" })
        hl(0, "BlinkCmpKindKeyword",     { fg = "#8be9fd" })
        hl(0, "BlinkCmpKindOperator",    { fg = "#8be9fd" })
        hl(0, "BlinkCmpKindSnippet",     { fg = "#f1fa8c" })
        hl(0, "BlinkCmpKindFile",        { fg = "#50fa7b" })
        hl(0, "BlinkCmpKindFolder",      { fg = "#50fa7b" })
        hl(0, "BlinkCmpKindModule",      { fg = "#ffb86c" })
        hl(0, "BlinkCmpKindClass",       { fg = "#ffb86c" })
        hl(0, "BlinkCmpKindStruct",      { fg = "#ffb86c" })
        hl(0, "BlinkCmpKindInterface",   { fg = "#ffb86c" })
        hl(0, "BlinkCmpKindConstant",    { fg = "#ff5555" })
        hl(0, "BlinkCmpKindEnum",        { fg = "#ff5555" })
        hl(0, "BlinkCmpKindEnumMember",  { fg = "#ff5555" })
        hl(0, "BlinkCmpKindText",        { fg = "#f8f8f2" })
        hl(0, "BlinkCmpKindValue",       { fg = "#f8f8f2" })
        hl(0, "BlinkCmpKindUnit",        { fg = "#f8f8f2" })
        hl(0, "BlinkCmpKindColor",       { fg = "#f8f8f2" })
        hl(0, "BlinkCmpKindReference",   { fg = "#f8f8f2" })
        hl(0, "BlinkCmpKindTypeParameter", { fg = "#8be9fd" })
    end,
}
