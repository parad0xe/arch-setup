-- =============================================================
-- lazy.nvim — the plugin manager.
-- It clones itself on first launch, then loads every file in
-- lua/plugins/ (each file returns a plugin spec).
-- Docs: https://lazy.folke.io
-- =============================================================

-- Download lazy.nvim once if it's missing.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	local repo = "https://github.com/folke/lazy.nvim.git"
	vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", repo, lazypath })
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({
			{ "Failed to clone lazy.nvim:\n", "ErrorMsg" },
			{ vim.fn.system({ "git", "clone", repo, lazypath }), "WarningMsg" },
			{ "\nPress any key to exit..." },
		}, true, {})
		vim.fn.getchar()
		os.exit(1)
	end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
	spec = {
		-- Every file in lua/plugins/ is a plugin spec; each one is
		-- loaded automatically.
		{ import = "plugins" },
	},
	-- Colorscheme used while plugins are installing.
	install = { colorscheme = { "habamax" } },
	-- Don't notify about plugin updates on every startup.
	checker = { enabled = false },
})
