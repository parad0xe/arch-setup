-- =============================================================
-- Global helper functions.
--
-- Why a separate file: some vim OPTIONS (like `foldtext`) can
-- only call *global* functions by name. Anything referenced that
-- way lives here, assigned to `_G` (the global namespace) —
-- the only place in the config where globals are acceptable.
-- Loaded from init.lua after options.lua.
-- =============================================================

-- The summary line shown for a closed fold, replacing Vim's ugly
-- default ("+-- 12 lines: ...") with:
--     <indent> 󰁂 <first line content>  •  <N> lines
function _G.custom_foldtext()
	local start = vim.v.foldstart
	local line = vim.fn.getline(start)

	-- Keep the original indentation so the fold text stays aligned.
	local indent = vim.fn.indent(start)
	local indent_str = string.rep(" ", indent)

	-- The first line's content, without its leading whitespace.
	local content = line:gsub("^%s*", "")

	local lines_count = vim.v.foldend - start + 1

	return indent_str .. "󰁂 " .. content .. "  •  " .. lines_count .. " lines"
end
