return {
	"folke/noice.nvim",
	enabled = true,
	event = "VeryLazy",
	dependencies = {
		"MunifTanjim/nui.nvim",
	},
	opts = {
		cmdline = {
			enabled = true,
			view = "cmdline_popup",
		},

		views = {
			cmdline_popup = {
				position = {
					row = 5,      -- top of screen
					col = "50%",  -- centered horizontally
				},
				size = {
					width = 60,
					height = "auto",
				},
				border = {
					style = "rounded",
				},
			},
		},
	},
	config = function(_, opts)
		require("noice").setup(opts)

		-- Apply highlights after colorscheme loads
		local function set_noice_highlights()
			-- Text you type in cmdline
			vim.api.nvim_set_hl(0, "NoiceCmdline", {
				fg = "#ff79c6", -- change to whatever color you like
				bg = "NONE",    -- transparent
			})

			-- Popup background transparent
			vim.api.nvim_set_hl(0, "NoiceCmdlinePopup", {
				bg = "NONE",
			})

			-- Popup border (optional styling)
			vim.api.nvim_set_hl(0, "NoiceCmdlinePopupBorder", {
				fg = "#8024ca",
				bg = "NONE",
			})

			-- Prompt text color
			vim.api.nvim_set_hl(0, "NoiceCmdlinePrompt", {
				fg = "#a6e3a1",
				bg = "NONE",
			})
		end

		-- Run immediately
		set_noice_highlights()

		-- Reapply after colorscheme changes
		vim.api.nvim_create_autocmd("ColorScheme", {
			callback = set_noice_highlights,
		})
	end,
}
