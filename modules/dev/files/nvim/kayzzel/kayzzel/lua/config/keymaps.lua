-- =============================================================
-- Personal keymaps — pure Neovim, no plugin dependencies.
-- Every mapping here should be one you actually use.
-- The leader key is <Space> (set in init.lua).
-- =============================================================

-- Small wrapper so every mapping gets a `desc` (shown by which-key)
-- and a silent remap.
local map = function(mode, lhs, rhs, desc)
	vim.keymap.set(mode, lhs, rhs, { desc = desc })
end

-- ── Files & windows ──────────────────────────────────────────
map("n", "<leader>w", "<cmd>w<cr>", "Write (save) file")
map("n", "<leader>q", "<cmd>q<cr>", "Quit window")
map("n", "<leader>Q", "<cmd>q!<cr>", "Force quit (discard changes)")
map("n", "<leader>x", "<cmd>x<cr>", "Save and quit")

-- ── Moving text ─────────────────────────────────────────────
-- Move selected lines up/down, keeping the selection selected
-- so you can repeat the motion.
map("x", "<C-j>", ":move '>+1<cr>gv-gv", "Move selection down")
map("x", "<C-k>", ":move '<-2<cr>gv-gv", "Move selection up")
-- Normal-mode versions: the V selects the current line first.
map("n", "<C-j>", "V:move '>+1<cr>gv-gv", "Move line down")
map("n", "<C-k>", "V:move '<-2<cr>gv-gv", "Move line up")

-- ── Centering ────────────────────────────────────────────────
-- Keep the cursor (and the match) in view while jumping around.
map("n", "<C-d>", "<C-d>zz", "Half page down, centered")
map("n", "<C-u>", "<C-u>zz", "Half page up, centered")
map("n", "n", "nzzzv", "Next search match, centered")
map("n", "N", "Nzzzv", "Previous search match, centered")

-- ── Visual mode niceties ────────────────────────────────────
-- Keep the selection after indenting, so you can adjust again.
map("v", "<", "<gv", "Indent left, keep selection")
map("v", ">", ">gv", "Indent right, keep selection")

-- Paste over a selection without losing the default register.
map("v", "<leader>p", '"_dP', "Paste over, keep register")

-- ── Buffers ─────────────────────────────────────────────────
-- Open a throwaway buffer: buftype=nofile means it isn't tied to
-- any file, bufhidden=wipe means it disappears when closed.
map("n", "<leader>bs", function()
	vim.cmd("enew")
	vim.bo.buftype = "nofile"
	vim.bo.bufhidden = "wipe"
	vim.notify("Scratch buffer opened")
end, "Open scratch buffer")

-- :%bd closes everything, e# reopens the last one, bd# removes it
-- from the buffer list — net effect: only this buffer survives.
map("n", "<leader>bo", ":%bd|e#|bd#<cr>", "Close all other buffers")

-- ── Tabs ────────────────────────────────────────────────────
map("n", "<leader>tn", "<cmd>tabnew<cr>", "New tab")
map("n", "<leader>to", "<cmd>tabonly<cr>", "Close all other tabs")
map("n", "<leader>tc", "<cmd>tabclose<cr>", "Close tab")
map("n", "<leader>tm", "<cmd>tabmove<cr>", "Move tab (prompts for index)")
map("n", "<leader>t<leader>", "<cmd>tabnext<cr>", "Next tab")

-- ── Folds ───────────────────────────────────────────────────
-- Fold motions live under the homerow neighbours of <leader>.
map("n", "<leader>:", "zc", "Close fold")
map("n", "<leader>;", "za", "Toggle fold")

-- ── Search & replace ─────────────────────────────────────────
-- Pre-fill :%s with the word under the cursor; the cursor lands
-- on the replacement so you can type it, then hit <cr>.
map(
	"n",
	"<leader>r",
	":%s/\\<<C-r><C-w>\\>/<C-r><C-w>/gI<Left><Left><Left>",
	"Replace word under cursor in file"
)
