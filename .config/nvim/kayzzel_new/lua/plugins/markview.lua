-- =============================================================
-- markview.nvim — live markdown previewer.
-- Renders the markdown line your cursor is NOT on (headers,
-- checkboxes, tables, code blocks); shows raw text while editing.
--
-- It also ships an emoji completion source for blink.cmp
-- (configured in blink.lua): type `:fi` in markdown to get 🔥.
-- =============================================================
return {
	"OXY2DEV/markview.nvim",
	lazy = false, -- no config needed: defaults render on markdown buffers
}
