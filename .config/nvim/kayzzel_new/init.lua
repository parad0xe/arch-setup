-- =============================================================
-- Entry point — the first file Neovim loads.
-- Kept tiny on purpose: it only wires the modules together.
-- =============================================================

-- The leader key must be set BEFORE plugins and keymaps are loaded,
-- otherwise plugin mappings using <leader> would capture the old value.
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Core: options first (sane defaults), then keymaps, then the plugin
-- manager (which in turn loads everything in lua/plugins/).
require("config.options")
require("config.functions")
require("config.keymaps")
require("config.diagnostics")
require("config.lazy")
