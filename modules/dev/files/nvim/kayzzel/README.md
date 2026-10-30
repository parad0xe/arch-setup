# 🌿 Neovim Config

Personal Neovim configuration built for **42 school** and general development.
Uses [lazy.nvim](https://github.com/folke/lazy.nvim) for plugin management and the [rose-pine](https://github.com/rose-pine/neovim) colorscheme.

---

## 📁 Structure

```
nvim/
├── init.lua                  # Entry point
├── lazy-lock.json            # Plugin version lockfile
└── lua/
    ├── config/
    │   └── lazy.lua          # Lazy.nvim bootstrap
    ├── core/
    │   ├── init.lua          # Loads core modules
    │   ├── keymaps.lua       # All custom keymaps
    │   └── options.lua       # Vim options & highlights
    └── plugins/              # One file per plugin
```

---

## ⚙️ Options

Configured in `lua/core/options.lua`.

| Option | Value | Description |
|---|---|---|
| `swapfile` | `false` | No swap files |
| `undofile` | `true` | Persistent undo history across sessions |
| `number` | `true` | Show line numbers |
| `relativenumber` | `true` | Show relative line numbers |
| `cursorline` | `true` | Highlight current line |
| `tabstop` | `4` | Tab width |
| `shiftwidth` | `4` | Indent width |
| `autoindent` | `true` | Auto-indent new lines |
| `scrolloff` | `15` | Keep 15 lines above/below cursor |
| `splitright` | `true` | Vertical splits open on the right |
| `splitbelow` | `true` | Horizontal splits open below |
| `termguicolors` | `true` | 24-bit color support |
| `foldmethod` | `expr` | Treesitter-based folding |
| `foldlevel` | `99` | All folds open by default |

### Highlights

| Group | Color | Description |
|---|---|---|
| `Visual` | `#6c4791` | Visual selection color |
| `DiagnosticError` | `#ff5555` | LSP error color |
| `DiagnosticWarn` | `#ff5555` | LSP warning color |

> To change the warning color back to yellow, uncomment the `#f1fa8c` lines in `options.lua`.

### Misc behaviors
- **Yank highlight** — yanked text flashes for 150ms
- **Custom foldtext** — folds display as `󰁂 content  •  N lines`
- **Lint on save** — flake8 and mypy run automatically on Python files if installed

---

## 🔌 Plugins

Managed by [lazy.nvim](https://github.com/folke/lazy.nvim). Each plugin has its own file in `lua/plugins/`.

### 🎨 UI

| Plugin | File | Description |
|---|---|---|
| [rose-pine](https://github.com/rose-pine/neovim) | `rose_pine.lua` | Colorscheme with transparent background |
| [noice.nvim](https://github.com/folke/noice.nvim) | `noice.lua` | Replaces cmdline UI with a centered popup |
| [fidget.nvim](https://github.com/j-hui/fidget.nvim) | `fidget.lua` | LSP progress spinner in the corner |
| [nvim-colorizer](https://github.com/norcalli/nvim-colorizer.lua) | `colorizer.lua` | Highlights hex color codes inline |
| [which-key.nvim](https://github.com/folke/which-key.nvim) | `wich_keys.lua` | Shows available keybinds as you type |

### 📁 File Navigation

| Plugin | File | Description |
|---|---|---|
| [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim) | `neo_tree.lua` | Sidebar file explorer |
| [oil.nvim](https://github.com/stevearc/oil.nvim) | `oil.lua` | Edit the filesystem like a buffer |
| [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) | `telescope.lua` | Fuzzy finder for files, grep, buffers |
| [harpoon](https://github.com/ThePrimeagen/harpoon) | `harpoon.lua` | Quick file bookmarking and jumping |
| [flash.nvim](https://github.com/folke/flash.nvim) | `flash.lua` | Fast cursor jumps with labels |

### ✏️ Editing

| Plugin | File | Description |
|---|---|---|
| [nvim-autopairs](https://github.com/windwp/nvim-autopairs) | `autopairs.lua` | Auto-closes brackets and quotes |
| [vim-surround](https://github.com/tpope/vim-surround) | `surround.lua` | Add/change/delete surrounding chars |
| [tabout.nvim](https://github.com/abecodes/tabout.nvim) | `tabout.lua` | Tab out of brackets/quotes in insert mode |
| [undotree](https://github.com/mbbill/undotree) | `undotree.lua` | Visual undo history tree |

### 🤖 LSP & Completion

| Plugin | File | Description |
|---|---|---|
| [mason.nvim](https://github.com/williamboman/mason.nvim) | `lsp.lua` | LSP server installer and manager |
| [mason-lspconfig](https://github.com/williamboman/mason-lspconfig.nvim) | `lsp.lua` | Bridges mason with nvim's LSP client |
| [blink.cmp](https://github.com/saghen/blink.cmp) | `blink.lua` | Completion engine with auto-import support |
| [friendly-snippets](https://github.com/rafamadriz/friendly-snippets) | `blink.lua` | Snippet collection for all languages |
| [nvim-lint](https://github.com/mfussenegger/nvim-lint) | `lint.lua` | Async linting (flake8, mypy for Python) |

### 🔧 LSP Servers (auto-installed by Mason)

| Server | Languages |
|---|---|
| `clangd` | C, C++, ObjC |
| `pyright` | Python |
| `ts_ls` | JavaScript, TypeScript, JSX, TSX |
| `rust_analyzer` | Rust |
| `lua_ls` | Lua |

> To add a new server: add its name to `ensure_installed` in `lsp.lua`, then add a `vim.lsp.config()` block for it.

### 🛠️ Tools

| Plugin | File | Description |
|---|---|---|
| [lazygit.nvim](https://github.com/kdheepak/lazygit.nvim) | `lazygit.lua` | Lazygit inside nvim |
| [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) | `toggleterm.lua` | Floating terminal + test file scratch pad |
| [markdown-preview](https://github.com/iamcco/markdown-preview.nvim) | `markdown.lua` | Live markdown preview in browser |
| [w3m.vim](https://github.com/yuratomo/w3m.vim) | `w3m.lua` | Web browser inside nvim |
| [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | `treesitter.lua` | Syntax highlighting and folding |

### 🏫 42 School

| Plugin | File | Description |
|---|---|---|
| [42-header.nvim](https://github.com/Diogo-ss/42-header.nvim) | `42header.lua` | Insert and auto-update 42 header |
| [42norm.nvim](https://github.com/MoulatiMehdi/42norm.nvim) | `42norm.lua` | Norminette integration and formatting |

> To change your 42 username and email, edit `user` and `mail` in `42header.lua`.

---

## ⌨️ Keymaps

`<leader>` is `Space`. Keymaps are defined in `lua/core/keymaps.lua` and individual plugin files.

### General

| Key | Mode | Action |
|---|---|---|
| `<leader>w` | Normal | Save file |
| `<leader>q` | Normal | Quit |
| `<leader>r` | Normal | Replace word under cursor (project-wide) |
| `<leader>bs` | Normal | Open scratch buffer |
| `<leader>bo` | Normal | Close all other buffers |
| `<leader>pd` | Normal | Disable a plugin temporarily |

### Movement

| Key | Mode | Action |
|---|---|---|
| `<C-u>` | Normal | Scroll half page up + center |
| `<C-d>` | Normal | Scroll half page down + center |
| `<C-k>` | Normal / Visual | Move line(s) up |
| `<C-j>` | Normal / Visual | Move line(s) down |
| `n` | Normal | Next search match + center |
| `N` | Normal | Previous search match + center |

### Editing

| Key | Mode | Action |
|---|---|---|
| `<` | Visual | Dedent and keep selection |
| `>` | Visual | Indent and keep selection |
| `<leader>p` | Visual | Paste without overwriting clipboard |

### Folds

| Key | Mode | Action |
|---|---|---|
| `<leader>:` | Normal | Close fold |
| `<leader>;` | Normal | Toggle fold |

### LSP (active in any buffer with a language server)

| Key | Mode | Action |
|---|---|---|
| `gd` | Normal | Go to definition |
| `K` | Normal | Hover documentation |
| `gi` | Normal | Go to implementation |
| `grn` | Normal | Rename symbol across project |
| `gra` | Normal | Code actions (fix, import, refactor) |
| `grr` | Normal | Show all references |

### Telescope

| Key | Mode | Action |
|---|---|---|
| `<space><space>` | Normal | Find files |
| `<space>fb` | Normal | Browse open buffers |
| `<space>li` | Normal | Live grep (search in files) |
| `<space>en` | Normal | Find files in nvim config |
| `<leader>gd` | Normal | Grep word under cursor |

### Harpoon

| Key | Mode | Action |
|---|---|---|
| `<leader>a` | Normal | Append current file to harpoon list |
| `<leader>a[1-9]` | Normal | Add current file to slot N |
| `<leader>[1-9]` | Normal | Jump to harpoon slot N |
| `<leader>d[1-9]` | Normal | Delete harpoon slot N |
| `<leader>D` | Normal | Clear all harpoon slots |
| `<C-e>` | Normal | Open harpoon list in Telescope |

### File Explorers

| Key | Mode | Action |
|---|---|---|
| `<leader>nt` | Normal | Toggle Neo-tree sidebar |
| `<leader>md` | Normal | Open Oil (filesystem editor) |

### Terminal

| Key | Mode | Action |
|---|---|---|
| `<leader>t` | Normal | Toggle floating terminal |
| `<C-t>` | Terminal | Toggle terminal from inside terminal |
| `<leader>e` | Normal | Open test file or terminal in temp dir |

### Git

| Key | Mode | Action |
|---|---|---|
| `<leader>lg` | Normal | Open Lazygit |

### Tools

| Key | Mode | Action |
|---|---|---|
| `<leader>ut` | Normal | Toggle Undotree |
| `<leader>h` | Normal | Insert 42 header |
| `<space>nr` | Normal | Run norminette |
| `<space>nf` | Normal | Format buffer with 42norm |
| `<space>m` | Normal | Toggle Markdown preview |
| `<leader>s` | Normal | Search the web with w3m |
| `<leader>?` | Normal | Show all keymaps (which-key) |

### Flash (jump)

| Key | Mode | Action |
|---|---|---|
| `zk` | Normal / Visual / Operator | Flash jump |
| `ZK` | Normal / Visual / Operator | Flash treesitter jump |
| `r` | Operator | Remote flash |
| `R` | Operator / Visual | Treesitter search |
| `<C-s>` | Command | Toggle flash in search |

### Completion (blink.cmp)

| Key | Mode | Action |
|---|---|---|
| `<C-space>` | Insert | Open completion menu |
| `<C-n>` / `<C-p>` | Insert | Next / previous item |
| `<Tab>` | Insert | Confirm selection |
| `<C-e>` | Insert | Close menu |

---

## 🎨 Customization

### Change colorscheme
Edit `lua/plugins/rose_pine.lua` — replace `"rose-pine"` with any colorscheme plugin.

### Change tab/indent size
Edit `tabstop` and `shiftwidth` in `lua/core/options.lua`.

### Add a new LSP server
1. Add the server name to `ensure_installed` in `lua/plugins/lsp.lua`
2. Add a `vim.lsp.config("server_name", { ... })` block
3. Add it to the `vim.lsp.enable({})` call
4. Run `:Mason` to install it

### Add a treesitter language
Add the language name to `ensure_installed` in `lua/plugins/treesitter.lua`, then run `:TSUpdate`.

### Disable a plugin
- **Temporarily:** press `<leader>pd` and type the plugin name, or open `:Lazy` and press `x`
- **Permanently:** set `enabled = false` in the plugin's file

### Change 42 header info
Edit `user` and `mail` in `lua/plugins/42header.lua`.

### Change noice cmdline position
Edit `row` and `col` in the `cmdline_popup` section of `lua/plugins/noice.lua`.

---

## 📦 Adding a new plugin

Create a new file in `lua/plugins/` following this template:

```lua
return {
    "author/plugin-name",
    event = "VeryLazy",   -- when to load (VeryLazy, BufEnter, InsertEnter...)
    dependencies = {},    -- other plugins it needs
    opts = {},            -- passed directly to require("plugin").setup()
    config = function()
        require("plugin").setup({})
        -- keymaps, highlights, etc.
    end,
}
```

Lazy picks up all files in `lua/plugins/` automatically — no registration needed.
