-- =============================================================
-- blink.cmp — completion engine (menu, snippets, signature help).
-- https://github.com/Saghen/blink.cmp
--
-- How it talks to the LSP plugin:
--   lsp.lua calls require("blink.cmp").get_lsp_capabilities()
--   so servers know we support resolve/snippets → that is what
--   makes auto-import work when you accept a completion.
-- =============================================================
return {
	"saghen/blink.cmp",
	version = "*", -- track the latest stable tag
	dependencies = {
		-- Snippet collection (vscode-style JSON) used by the
		-- "snippets" source; blink renders them natively.
		"rafamadriz/friendly-snippets",
	},

	opts = {
		-- ── Keymaps ─────────────────────────────────────────────
		keymap = {
			preset = "default", -- C-space open, C-e close
			["<Tab>"] = { "accept", "fallback" }, -- Tab confirms; else falls through (indent/snippet jump)
			["<CR>"] = { "fallback" }, -- Enter NEVER confirms, always newline
			["<C-x>"] = { "select_next", "fallback" }, -- next item
			["<C-p>"] = { "select_prev", "fallback" }, -- previous item
		},

		-- ── Appearance ─────────────────────────────────────────
		appearance = {
			nerd_font_variant = "mono", -- pick icons matching your font
			kind_icons = {
				Text = "󰉿",
				Method = "󰆧",
				Function = "󰊕",
				Constructor = "",
				Field = "󰜢",
				Variable = "󰀫",
				Class = "󰠱",
				Interface = "",
				Module = "",
				Property = "󰜢",
				Unit = "󰑭",
				Value = "󰎠",
				Enum = "",
				Keyword = "󰌋",
				Snippet = "",
				Color = "󰏘",
				File = "󰈙",
				Reference = "󰈇",
				Folder = "󰉋",
				EnumMember = "",
				Constant = "󰏿",
				Struct = "󰙅",
				Event = "",
				Operator = "󰆕",
				TypeParameter = "",
			},
		},

		-- ── Sources ────────────────────────────────────────────
		-- Order = priority: LSP suggestions first, then path paths,
		-- then snippets, then plain words found in open buffers.
		sources = {
			default = { "lsp", "path", "snippets", "buffer" },
		},

		completion = {
			-- Show the menu as soon as you start typing / type a
			-- trigger character like `.` or `::`.
			trigger = {
				show_on_insert_enter = true,
				show_on_trigger_character = true,
			},

			-- First item is preselected; confirming inserts it.
			list = {
				selection = {
					preselect = true,
					auto_insert = false,
				},
			},

			-- How each row is drawn: icon | label | kind | source.
			menu = {
				border = "rounded",
				winhighlight = "Normal:BlinkCmpMenu,FloatBorder:BlinkCmpMenuBorder,CursorLine:BlinkCmpMenuSelection",
				draw = {
					columns = {
						{ "kind_icon", gap = 1 },
						{ "label", "label_description", gap = 1 },
						{ "kind", gap = 1 },
						{ "source_name" },
					},
				},
			},

			-- Doc popup next to the menu, after a short delay.
			documentation = {
				auto_show = true,
				auto_show_delay_ms = 200,
				window = { border = "rounded" },
			},

			-- Accept behavior. auto_brackets adds () after
			-- confirming a function. Auto-imports (adding the
			-- missing `import` line) are handled natively: blink
			-- resolves the item and applies the server's extra
			-- text edits — no custom on_accept hook needed.
			accept = {
				auto_brackets = { enabled = true },
			},
		},

		-- Function signature popup while typing arguments.
		signature = {
			enabled = true,
			window = { border = "rounded" },
		},
	},

	-- ── Theming ─────────────────────────────────────────────
	-- Custom highlights: dark menu + purple accents (overrides
	-- rose-pine's blink colors — that's intentional, it's the
	-- "purple noice" look from the old config).
	config = function(_, opts)
		require("blink.cmp").setup(opts)

		local hl = vim.api.nvim_set_hl

		-- Menu windows
		hl(0, "BlinkCmpMenu", { bg = "#1a1a2e" })
		hl(0, "BlinkCmpMenuBorder", { fg = "#8024ca", bg = "NONE" })
		hl(0, "BlinkCmpMenuSelection", { bg = "#6c4791" })

		-- Documentation popup
		hl(0, "BlinkCmpDoc", { bg = "#1a1a2e" })
		hl(0, "BlinkCmpDocBorder", { fg = "#8024ca", bg = "NONE" })

		-- Signature help
		hl(0, "BlinkCmpSignatureHelp", { bg = "#1a1a2e" })
		hl(0, "BlinkCmpSignatureHelpBorder", { fg = "#8024ca", bg = "NONE" })

		-- Kind icon colors (what each completion *is*)
		hl(0, "BlinkCmpKindFunction", { fg = "#ff79c6" })
		hl(0, "BlinkCmpKindMethod", { fg = "#ff79c6" })
		hl(0, "BlinkCmpKindConstructor", { fg = "#ff79c6" })
		hl(0, "BlinkCmpKindVariable", { fg = "#bd93f9" })
		hl(0, "BlinkCmpKindField", { fg = "#bd93f9" })
		hl(0, "BlinkCmpKindProperty", { fg = "#bd93f9" })
		hl(0, "BlinkCmpKindKeyword", { fg = "#8be9fd" })
		hl(0, "BlinkCmpKindOperator", { fg = "#8be9fd" })
		hl(0, "BlinkCmpKindSnippet", { fg = "#f1fa8c" })
		hl(0, "BlinkCmpKindFile", { fg = "#50fa7b" })
		hl(0, "BlinkCmpKindFolder", { fg = "#50fa7b" })
		hl(0, "BlinkCmpKindModule", { fg = "#ffb86c" })
		hl(0, "BlinkCmpKindClass", { fg = "#ffb86c" })
		hl(0, "BlinkCmpKindStruct", { fg = "#ffb86c" })
		hl(0, "BlinkCmpKindInterface", { fg = "#ffb86c" })
		hl(0, "BlinkCmpKindConstant", { fg = "#ff5555" })
		hl(0, "BlinkCmpKindEnum", { fg = "#ff5555" })
		hl(0, "BlinkCmpKindEnumMember", { fg = "#ff5555" })
		hl(0, "BlinkCmpKindText", { fg = "#f8f8f2" })
		hl(0, "BlinkCmpKindValue", { fg = "#f8f8f2" })
		hl(0, "BlinkCmpKindUnit", { fg = "#f8f8f2" })
		hl(0, "BlinkCmpKindColor", { fg = "#f8f8f2" })
		hl(0, "BlinkCmpKindReference", { fg = "#f8f8f2" })
		hl(0, "BlinkCmpKindTypeParameter", { fg = "#8be9fd" })
	end,
}
