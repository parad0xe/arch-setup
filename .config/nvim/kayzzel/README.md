# Neovim Config — kayzzel

Personal Neovim configuration, rebuilt from scratch with one rule:
**every line is understood and can be explained**. One file per concern, comments
everywhere, no magic. Built for daily coding (C, Python, TypeScript, Rust, Lua)
and 42 school projects.

- **Neovim**: 0.11+ required (uses the `vim.lsp.config` / `vim.lsp.enable` API) — 0.12 tested
- **Plugin manager**: [lazy.nvim](https://github.com/folke/lazy.nvim) (auto-clones on first launch)
- **Colorscheme**: rose-pine (transparent) + custom purple accents
- **Leader key**: `<Space>`

---

## Requirements

| Tool | Needed for | Required |
|---|---|---|
| Neovim ≥ 0.11 | the whole config | ✅ |
| `git` | plugin installation | ✅ |
| `make` + C compiler | telescope fzf-native sorter, treesitter parsers | ✅ |
| a Nerd Font | icons everywhere | ✅ |
| `yazi` | file manager integration | ✅ |
| `ripgrep` (`rg`) | telescope `live_grep` | recommended |
| `flake8`, `mypy` | python linting (only registered if installed) | optional |
| `ueberzugpp` | image previews inside yazi (nvim terminal can't do graphics protocols) | optional |

---

## File structure

```
nvim/kayzzel/
├── init.lua                  # Entry point: leader → options → functions → keymaps
│                             #   → diagnostics → lazy → appearance (order matters!)
├── lazy-lock.json            # Pinned plugin versions (commit it!)
├── doc/
│   ├── vim_keybind.md        # Native keybind cheatsheet (Part 1: Vim / Part 2: Neovim)
│   └── vim_command.md        # Native command cheatsheet (same split)
└── lua/
    ├── config/               # ── Core (no plugins) ──
    │   ├── options.lua       # All vim options + folding setup
    │   ├── keymaps.lua       # All personal, plugin-independent mappings
    │   ├── functions.lua     # _G globals referenced by options (custom foldtext)
    │   ├── diagnostics.lua   # How lint/LSP diagnostics are displayed
    │   ├── python.lua        # Venv/poetry detection (shared by lint + pyright)
    │   ├── appearance.lua    # Highlight overrides, applied AFTER the colorscheme
    │   └── lazy.lua          # lazy.nvim bootstrap; imports lua/plugins/*
    └── plugins/             # ── One file per plugin ──
        ├── rose-pine.lua     # colorscheme (transparent background)
        ├── treesitter.lua    # parsers + highlighting + indent (main branch API)
        ├── blink.lua         # completion engine (menu, snippets, signature help)
        ├── lsp.lua           # mason + lspconfig + per-server settings + keymaps
        ├── lint.lua           # nvim-lint (flake8 + strict mypy on the right venv)
        ├── autopairs.lua     # bracket pairs (+ fast_wrap, treesitter-aware)
        ├── telescope.lua     # fuzzy finder + fzf-native + all its keymaps
        ├── telescope-undo.lua # undo history as a searchable tree
        ├── toggleterm.lua    # persistent floating terminal
        ├── yazi.lua          # yazi file manager, embedded
        ├── markview.lua      # live markdown preview (+ emoji completion source)
        ├── refactor.lua      # ThePrimeagen refactoring.nvim (extract/inline/debug)
        ├── flash.lua         # treesitter-powered jump motions
        ├── whichkey.lua      # keymap discovery popup
        ├── lazygit.lua       # lazygit in a floating window
        ├── noice.lua         # redesigned cmdline / messages UI
        ├── fidget.lua        # LSP progress notifications
        ├── colorizer.lua     # colorize #hex codes, rgb(), etc.
        └── surround.lua      # add/change/delete surrounding pairs (ys/cs/ds)
```

---

## Options (`lua/config/options.lua`)

| Option | Value | Why |
|---|---|---|
| `mapleader` | `<Space>` | set in `init.lua`, **before** plugins |
| `swapfile` | off | no `.swp` clutter |
| `undofile` | on | undo history survives sessions |
| `updatetime` | 250 ms | snappier UI events (default 4000) |
| `timeoutlen` | 400 ms | wait time for `<leader>` sequences |
| `number` + `relativenumber` | on | absolute on current line, relative elsewhere (`5j`) |
| `cursorline` | on | highlighted (but background transparent — see appearance) |
| `tabstop` / `shiftwidth` | 4 + `expandtab` | spaces, always |
| `smartindent` | on | context-aware auto-indent |
| `scrolloff` | 10 | cursor never touches screen edges |
| `splitbelow` / `splitright` | on | splits open where you expect |
| `ignorecase` + `smartcase` | on | case-insensitive until you type a capital |
| `hlsearch` | off | no lingering search highlights |
| `clipboard` | `unnamedplus` | one shared system clipboard |
| `foldmethod` | `expr` | **treesitter folding** (+ LSP folding per buffer, see LSP) |
| `foldtext` | custom | `󰁂 <first line> • N lines` (defined in `functions.lua`) |

---

## Appearance

- **rose-pine**, `main` variant, transparent background & floats.
- Purple accent shared everywhere — **selection** (`Visual` = `#6c4791` + blend),
  **blink menu** (selection bg `#6c4791`, borders `#8024ca`, dark `#1a1a2e` menus),
  **current line number** (`CursorLineNr` = `#bd93f9`, bold).
- Transparent `StatusLine` / `CursorLine` bands.
- All overrides live in `lua/config/appearance.lua`, loaded **after** the
  colorscheme and re-applied on `ColorScheme` events — so they always win.

---

## Plugins

| Plugin | Role | Loaded |
|---|---|---|
| [lazy.nvim](https://github.com/folke/lazy.nvim) | plugin manager | first launch |
| [rose-pine](https://github.com/rose-pine/neovim) | colorscheme | startup |
| [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) (main branch) | 25 parsers, highlighting, indent | startup |
| [blink.cmp](https://github.com/Saghen/blink.cmp) | completion: LSP, paths, snippets, buffer | insert mode |
| [mason.nvim](https://github.com/williamboman/mason.nvim) | installs LSP servers (auto) | startup |
| [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) | default server configs | startup |
| [nvim-lint](https://github.com/mfussenegger/nvim-lint) | flake8 + strict mypy, venv-aware | startup |
| [nvim-autopairs](https://github.com/windwp/nvim-autopairs) | auto-close pairs, treesitter-aware | insert mode |
| [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) + fzf-native | fuzzy finder | on key |
| [telescope-undo](https://github.com/debugloop/telescope-undo.nvim) | searchable undo tree | on key |
| [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) | persistent floating terminal | on key |
| [yazi.nvim](https://github.com/mikavilpas/yazi.nvim) | file manager embedded (replaces netrw) | on key |
| [markview.nvim](https://github.com/OXY2DEV/markview.nvim) | markdown live preview + emoji source | startup |
| [refactoring.nvim](https://github.com/ThePrimeagen/refactoring.nvim) | extract/inline refactors, debug prints | on key |
| [flash.nvim](https://github.com/folke/flash.nvim) | jump motions, treesitter select | on key |
| [which-key.nvim](https://github.com/folke/which-key.nvim) | keymap discovery | VeryLazy |
| [lazygit.nvim](https://github.com/kdheepak/lazygit.nvim) | lazygit float | on key |
| [noice.nvim](https://github.com/folke/noice.nvim) | cmdline / message UI | VeryLazy |
| [fidget.nvim](https://github.com/j-hui/fidget.nvim) | LSP progress spinner | startup |
| [nvim-colorizer](https://github.com/norcalli/nvim-colorizer.lua) | highlight color codes | startup |
| [vim-surround](https://github.com/tpope/vim-surround) | `ys`/`cs`/`ds` surroundings | startup |

---

## Language servers

Defined in `lua/plugins/lsp.lua`, auto-installed by mason on first launch:

| Server | Language | Notable settings |
|---|---|---|
| `lua_ls` | Lua | `vim` as a known global |
| `pyright` | Python | pointed at the project venv (via `python.lua`), auto-imports, `basic` type checking |
| `ts_ls` | TypeScript / JS | relative import paths |
| `clangd` | C / C++ | `--background-index`, `--clang-tidy` |
| `rust_analyzer` | Rust | module-group imports, all cargo features, proc macros |

Capabilities are handed to blink.cmp (`get_lsp_capabilities()`) so completion,
snippets and auto-imports all work. Folding: treesitter by default, `vim.lsp.foldexpr()`
per buffer when the server supports `foldingRange`.

---

## Keybinds

`<leader>` = `<Space>`. All mappings have a `desc` — press `<leader>?` (which-key) or
`<leader>k` (telescope) to browse them live.

### Core — `lua/config/keymaps.lua`

| Key | Mode | Action |
|---|---|---|
| `<leader>w` / `q` / `Q` / `x` | n | write / quit / force quit / save+quit |
| `<C-j>` / `<C-k>` | n, x | move line (or selection) down / up |
| `<C-d>` / `<C-u>` | n | half-page jump, centered |
| `n` / `N` | n | next / previous match, centered |
| `<` / `>` | v | indent, keep selection |
| `<leader>p` | v | paste over selection, keep register |
| `<leader>r` | n | replace word under cursor in file |
| `<leader>bs` | n | open scratch buffer |
| `<leader>bo` | n | close all other buffers |
| `<leader>tn` / `to` / `tc` / `tm` / `t<Space>` | n | new / only / close / move / next tab |
| `<leader>:` / `<leader>;` | n | close fold / toggle fold |

### LSP — buffer-local, set when a server attaches

| Key | Action |
|---|---|
| `gd` | go to definition (telescope) |
| `gi` | go to implementation (telescope) |
| `K` | hover documentation |
| `grr` | references (telescope) |
| `grn` | rename symbol |
| `gra` | code action |
| `gO` | document symbols outline (native 0.11+) |

### Telescope

| Key | Action |
|---|---|
| `<Space><Space>` | find files |
| `<leader>fb` | buffers |
| `<leader>li` | live grep |
| `<leader>en` | find files in nvim config |
| `<leader>gd` | grep word under cursor |
| `<leader>ds` / `<leader>ws` | document / workspace symbols |
| `<leader>dg` | diagnostics (all buffers) |
| `<leader>gc` / `gb` / `gs` | git commits / branches / status |
| `<leader>k` | search all keymaps |
| `<leader>ut` | undo history (telescope-undo) |

### Refactoring (visual selection, or motion in normal mode)

| Key | Action |
|---|---|
| `<leader>re` / `<leader>ree` | extract function (selection / line) |
| `<leader>rE` | extract function to file |
| `<leader>rv` / `<leader>rvv` | extract variable (selection / line) |
| `<leader>ri` / `<leader>rI` | inline variable / inline function |
| `<leader>rr` | pick a refactoring from a list |
| `<leader>rd` / `<leader>rp` | debug: print var below / above |
| `<leader>rc` | debug: cleanup prints |

### File manager / terminal / git

| Key | Action |
|---|---|
| `<leader>md` | yazi (hover + `q` opens the file here; replaces netrw) |
| `<leader>tt` | toggle floating terminal |
| `<C-t>` | close it from inside terminal mode |
| `<leader>lg` | lazygit floating window |

### Flash (jump motions)

| Key | Mode | Action |
|---|---|---|
| `<Space>k` | n, x, o | jump anywhere (labeled) |
| `<Space>K` | n, x, o | select a treesitter node |
| `r` | o | remote (operator) jump |
| `R` | o, x | treesitter search |
| `<C-s>` | c | toggle flash in `/` search |

### Misc

| Key | Action |
|---|---|
| `<leader>?` | which-key: browse all `<leader>` mappings |
| `ys` / `cs` / `ds` + pair | vim-surround: add / change / delete surroundings |
| `<A-e>` after an opening pair | autopairs fast-wrap |

---

## Linting

`lua/plugins/lint.lua` — for Python, and only if the tools exist on the system:

- **flake8** — style
- **mypy** — `--strict`, `--cache-dir=/dev/null`, `--python-executable` set to the
  detected venv (`lua/config/python.lua` looks in `.venv/`, `venv/`, `env/`, then poetry,
  then system python; cached per session)

Linters re-run on save, insert-leave, and file open — but only for filetypes that
have one. Diagnostics display: `▎` virtual text in red, signs in the gutter,
severity-sorted (`lua/config/diagnostics.lua`).

---

## First launch (what downloads what)

1. **lazy.nvim** clones itself, then installs all plugins.
2. **mason** downloads the 5 LSP servers in the background — servers won't attach
   until the *next* launch.
3. **treesitter** downloads and compiles 25 parsers — buffers opened during the
   download highlight after reopening.

So: launch once, wait a minute, restart. Everything is then pinned via
`lazy-lock.json`.

---

## Docs

- `doc/vim_keybind.md` — every native keybind, split in **Part 1 — Vim**
  (works in classic Vim) and **Part 2 — Neovim only** (terminal, LSP).
- `doc/vim_command.md` — every useful command, same split
  (`:g`, ranges, `:norm`, `:lua`, health & inspect, ...).
