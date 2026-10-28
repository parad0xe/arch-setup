-- =============================================================
-- Appearance overrides (on top of rose-pine).
--
-- Ordering matters: a colorscheme REDEFINES highlight groups,
-- so these must run AFTER it. init.lua loads this file after
-- lazy (and after rose-pine), and the ColorScheme autocmd below
-- re-applies everything when you switch themes — so these
-- overrides always win.
-- =============================================================
local hl = vim.api.nvim_set_hl

local function apply_overrides()
	-- Transparent statusline: no colored band at the bottom.
	hl(0, "StatusLine", { bg = "none" })
	hl(0, "StatusLineNC", { bg = "none" })

	-- Keep the cursorline indicator, but no colored band.
	hl(0, "CursorLine", { bg = "none" })

	-- Current line number in purple (bd93f9 = readable bright
	-- purple; the old config's #8024ca is darker/less legible).
	hl(0, "CursorLineNr", { fg = "#bd93f9" })

	-- Purple semi-transparent visual selection — the same
	-- #6c4791 as the blink.cmp selection background, so the
	-- whole UI shares one purple.
	hl(0, "Visual", { bg = "#6c4791", blend = 10 })
end

apply_overrides()

vim.api.nvim_create_autocmd("ColorScheme", {
	callback = apply_overrides,
})
