-- =============================================================
-- All vim options in one place.
-- Tip: `:h 'optionname'` (note the quotes) opens the doc for any
-- option used here.
-- =============================================================
local opt = vim.opt

-- ── Files ───────────────────────────────────────────────────
opt.swapfile = false -- never create .swp files
opt.undofile = true -- keep undo history across sessions (in ~/.local/share/nvim/undo)
opt.updatetime = 250 -- ms to wait before writing swap / firing CursorHold events
opt.timeoutlen = 400 -- ms to wait for the next key after <leader>

-- ── Appearance ──────────────────────────────────────────────
opt.number = true -- absolute line number on the cursor line
opt.relativenumber = true -- all other lines are relative (easy 5j / 3k)
opt.cursorline = true -- highlight the line the cursor is on
opt.termguicolors = true -- true colors, required by modern colorschemes
opt.signcolumn = "yes" -- always reserve the sign column (no shifting text)
opt.scrolloff = 10 -- keep at least 10 lines visible above/below the cursor
opt.splitright = true -- vertical splits open on the right
opt.splitbelow = true -- horizontal splits open below

-- ── Tabs & indentation ──────────────────────────────────────
opt.tabstop = 4 -- width a tab character displays as
opt.shiftwidth = 4 -- width used by << >> and auto-indent
opt.expandtab = true -- insert spaces instead of tab characters
opt.smartindent = true -- auto-indent new lines based on context
opt.backspace = "indent,eol,start" -- backspace behaves as expected

-- ── Search ──────────────────────────────────────────────────
opt.ignorecase = true -- search is case-insensitive...
opt.smartcase = true -- ...until you type a capital letter
opt.hlsearch = false -- don't leave search results highlighted

-- ── Clipboard ───────────────────────────────────────────────
opt.clipboard = "unnamedplus" -- yank/paste share the system clipboard

-- ── Folding ─────────────────────────────────────────────────
-- Treesitter folding: folds are function/class blocks, from the
-- syntax tree (needs a parser for the filetype — treesitter.lua).
opt.foldmethod = "expr"
opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
opt.foldlevel = 99 -- start with all folds open
opt.foldlevelstart = 99
opt.fillchars = { fold = " " } -- clean fold gutter

-- The fold summary line is drawn by _G.custom_foldtext(),
-- defined in lua/config/functions.lua.
vim.opt.foldtext = "v:lua.custom_foldtext()"
