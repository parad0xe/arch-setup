# Neovim Native Commands — Cheatsheet

> From beginner to expert. Everything here is stock — no plugins needed.
> Plugin commands (like `:Lazy`, `:Mason`, `:Yazi`) are listed by `:command`.
>
> Two parts: **Part 1 — Vim** (works in classic Vim too) and **Part 2 — Neovim only**.

## Part 1 — Vim (works in classic Vim too)

### Files

| Command | Action |
|---|---|
| `:e [file]` | Open / edit a file |
| `:e!` | Reload current file, discard changes |
| `:e .` | Open netrw file explorer in current dir |
| `:w` | Save current file |
| `:w [file]` | Save as `[file]` |
| `:w!` | Force save (overwrite read-only) |
| `:wa` | Save all open buffers |
| `:q` | Quit |
| `:q!` | Quit without saving |
| `:wq` | Save and quit |
| `:x` | Save and quit (only writes if modified) |
| `:qa` | Quit all windows |
| `:qa!` | Quit all without saving |
| `:saveas [file]` | Save file under new name and switch to it |
| `:r [file]` | Insert content of file below cursor |
| `:r! [cmd]` | Insert output of shell command below cursor |

### Buffers

| Command | Action |
|---|---|
| `:ls` | List all open buffers |
| `:buffers` | Same as `:ls` |
| `:b [n]` | Switch to buffer number n |
| `:b [name]` | Switch to buffer by name (partial match ok) |
| `:bn` | Next buffer |
| `:bp` | Previous buffer |
| `:bd` | Delete (close) current buffer |
| `:bd [n]` | Delete buffer n |
| `:bw` | Wipe buffer (fully remove from memory) |
| `:ball` | Open all buffers in splits |
| `:bufdo [cmd]` | Run command on all buffers (e.g. `:bufdo w`) |

### Windows & Splits

| Command | Action |
|---|---|
| `:sp [file]` | Horizontal split (open file or current) |
| `:vsp [file]` | Vertical split |
| `:new` | New horizontal split with empty buffer |
| `:vnew` | New vertical split with empty buffer |
| `:only` | Close all splits except current |
| `:close` | Close current split |
| `:resize [n]` | Set split height to n lines |
| `:resize +n` | Increase split height |
| `:resize -n` | Decrease split height |
| `:vertical resize [n]` | Set split width to n columns |
| `:windo [cmd]` | Run command in all windows (e.g. `:windo q`) |

### Tabs

| Command | Action |
|---|---|
| `:tabnew [file]` | Open file in new tab |
| `:tabn` | Next tab |
| `:tabp` | Previous tab |
| `:tabclose` | Close current tab |
| `:tabonly` | Close all other tabs |
| `:tabmove [n]` | Move tab to position n |
| `:tabdo [cmd]` | Run command in all tabs (e.g. `:tabdo w`) |
| `:tabs` | List all tabs and their windows |

### Search & Substitute

| Command | Action |
|---|---|
| `:s/old/new/` | Replace first match on current line |
| `:s/old/new/g` | Replace all matches on current line |
| `:%s/old/new/g` | Replace all matches in file |
| `:%s/old/new/gc` | Replace all with confirmation (y/n/a/q) |
| `:%s/old/new/gi` | Replace all, case insensitive |
| `:%s/old/new/gI` | Replace all, force case sensitive |
| `:5,10s/old/new/g` | Replace in lines 5 to 10 |
| `:'<,'>s/old/new/g` | Replace in visual selection |
| `:noh` | Clear search highlight |

Special replace chars:

| Char | Action |
|---|---|
| `&` | The matched text (e.g. `:%s/foo/[&]/` → `[foo]`) |
| `\1` `\2` | Backreferences to capture groups |
| `\u` | Uppercase next char |
| `\l` | Lowercase next char |
| `\U...\E` | Uppercase until `\E` |
| `\L...\E` | Lowercase until `\E` |

### Ranges

Ranges can be prepended to most commands:

| Range | Meaning |
|---|---|
| `:5` | Line 5 |
| `:5,10` | Lines 5 to 10 |
| `:%` | Entire file (same as `1,$`) |
| `:.` | Current line |
| `:$` | Last line |
| `:.,$` | Current line to end |
| `:1,.` | Start to current line |
| `:'<,'>` | Visual selection (auto-filled with `v:`) |
| `:/pattern/` | Line matching pattern |
| `:/pat1/,/pat2/` | From pattern 1 to pattern 2 |

Examples:

| Command | Action |
|---|---|
| `:5,10d` | Delete lines 5 to 10 |
| `:5,10y` | Yank lines 5 to 10 |
| `:5,10m 20` | Move lines 5-10 after line 20 |
| `:5,10co 0` | Copy lines 5-10 before line 1 |
| `:%d` | Delete all lines |
| `:%y+` | Yank entire file to clipboard |

### Editing Commands

| Command | Action |
|---|---|
| `:d [reg]` | Delete current line (into register) |
| `:y [reg]` | Yank current line (into register) |
| `:pu [reg]` | Paste register below current line |
| `:co [line]` | Copy current line after `[line]` |
| `:m [line]` | Move current line after `[line]` |
| `:j` | Join current line with next |
| `:ce [width]` | Center text (default width 80) |
| `:le [indent]` | Left-align text with indent |
| `:ri [width]` | Right-align text |
| `:sort` | Sort selected/all lines alphabetically |
| `:sort!` | Sort in reverse |
| `:sort n` | Sort numerically |
| `:sort u` | Sort and remove duplicates |
| `:sort i` | Sort case insensitive |
| `:retab` | Convert tabs to spaces (or vice versa) |
| `:retab!` | Force retab with current tabstop |
| `:%!fmt` | Format file with external `fmt` command |
| `:%!sort` | Sort file with external `sort` |
| `:%!column -t` | Align columns with external `column` command |

### Options (`:set`)

| Command | Action |
|---|---|
| `:set` | Show all modified options |
| `:set all` | Show all options |
| `:set [option]` | Enable boolean option |
| `:set no[option]` | Disable boolean option |
| `:set [option]!` | Toggle boolean option |
| `:set [option]?` | Show current value of option |
| `:set [option]=[val]` | Set option value |

Useful options to toggle on the fly:

| Command | Action |
|---|---|
| `:set number` | Show line numbers |
| `:set relativenumber` | Show relative line numbers |
| `:set wrap` / `:set nowrap` | Toggle line wrapping |
| `:set spell` | Enable spell checking |
| `:set list` | Show hidden chars (tabs, trailing spaces) |
| `:set hlsearch` | Highlight search matches |
| `:set ignorecase` | Case insensitive search |
| `:set smartcase` | Smart case (case sensitive if uppercase used) |
| `:set expandtab` | Use spaces instead of tabs |
| `:set tabstop=4` | Set tab width |
| `:set shiftwidth=4` | Set indent width |
| `:set colorcolumn=80` | Show column guide at 80 chars |
| `:set cursorline` | Highlight current line |
| `:set scrolloff=8` | Keep 8 lines visible above/below cursor |
| `:set conceallevel=0` | Disable text concealing (e.g. in markdown) |

### Marks

| Command | Action |
|---|---|
| `:marks` | List all marks |
| `:marks [a-z]` | Show specific marks |
| `:delmarks [marks]` | Delete specific marks (e.g. `:delmarks abc`) |
| `:delmarks!` | Delete all lowercase marks |

### Registers

| Command | Action |
|---|---|
| `:reg` | Show all register contents |
| `:reg [a-z]` | Show specific register (e.g. `:reg a`) |

### Shell & External

| Command | Action |
|---|---|
| `:! [cmd]` | Run shell command (output shown, file unchanged) |
| `:!! [cmd]` | Re-run last shell command |
| `:sh` | Open a shell (exit to return to nvim) |
| `:terminal` | Open terminal inside nvim buffer |
| `:[range]! [cmd]` | Filter range through external command (e.g. `:%!sort`) |
| `:redir @a>` | Capture subsequent command output into register a (end with `:redir END`) |
| `:make` | Run makeprg (default: `make`) |
| `:make [target]` | Run make with target |
| `:compiler [name]` | Set compiler plugin |
| `:copen` | Open quickfix (shows make errors) |

### Quickfix & Location List

| Command | Action |
|---|---|
| `:copen` | Open quickfix list |
| `:cclose` | Close quickfix list |
| `:cn` | Next entry |
| `:cp` | Previous entry |
| `:cfirst` | First entry |
| `:clast` | Last entry |
| `:cc [n]` | Jump to entry n |
| `:cdo [cmd]` | Run command on each quickfix entry |
| `:cfdo [cmd]` | Run command on each file in quickfix |
| `:lopen` | Open location list (window-local quickfix) |
| `:lclose` | Close location list |
| `:ln` | Next location entry |
| `:lp` | Previous location entry |
| `:lfirst` / `:llast` | First / last location entry |

### Grep & Search in Files

| Command | Action |
|---|---|
| `:grep [pattern] [files]` | Search using grepprg (default: grep) |
| `:grep -r foo src/` | Recursive grep in src/ |
| `:vimgrep /pattern/ %` | Search in current file (`:vim` == `:vimgrep`) |
| `:vimgrep /pattern/ **/*.c` | Search in all .c files recursively |
| `:copen` | See results in quickfix list |
| `:set grepprg=rg\ --vimgrep` | Use ripgrep instead of grep |

### Spell Checking

| Command | Action |
|---|---|
| `:set spell` / `:set nospell` | Enable / disable spell checking |
| `:set spelllang=en_us` | Set language |
| `:set spelllang=fr` | Set to French |
| `:spellgood [word]` | Add word to dictionary |
| `:spellwrong [word]` | Mark word as wrong |
| `:spellundo [word]` | Undo spellgood/spellwrong |
| `:runtime spell/cleanadd.vim` | Clean spell file |

### Global Command

| Command | Action |
|---|---|
| `:g/pattern/[cmd]` | Run cmd on every line matching pattern |
| `:g!/pattern/[cmd]` | Run cmd on every line NOT matching pattern |
| `:v/pattern/[cmd]` | Same as `:g!` (v = inVert) |

Examples:

| Command | Action |
|---|---|
| `:g/TODO/p` | Print all lines containing TODO |
| `:g/^$/d` | Delete all empty lines |
| `:g/foo/d` | Delete all lines containing "foo" |
| `:g/foo/s/bar/baz/g` | On lines with "foo", replace bar→baz |
| `:g/pattern/y A` | Append all matching lines to register a |
| `:g/^/m 0` | Reverse order of all lines |
| `:g/pattern/norm @q` | Apply macro q to all matching lines |
| `:g/pattern/t $` | Copy all matching lines to end of file |
| `:g/^\s*$/d` | Delete all blank/whitespace-only lines |
| `:g/pattern/norm dd` | Delete lines matching pattern (via normal) |

### Normal Command

| Command | Action |
|---|---|
| `:norm [keys]` | Execute normal mode keys on current line |
| `:[range]norm [keys]` | Execute on a range of lines |

Examples:

| Command | Action |
|---|---|
| `:%norm A;` | Append semicolon to every line |
| `:%norm I// ` | Comment every line with `//` |
| `:5,10norm dd` | Delete lines 5 to 10 via normal mode |
| `:'<,'>norm @q` | Apply macro q to visual selection |
| `:%norm ^x` | Delete first char of every line |

### Keymaps & Commands

| Command | Action |
|---|---|
| `:map` | List all mappings |
| `:nmap` | List normal mode mappings |
| `:imap` | List insert mode mappings |
| `:vmap` | List visual mode mappings |
| `:map [key] [action]` | Map key in normal+visual |
| `:nmap [key] [action]` | Map key in normal mode |
| `:nnoremap [key] [action]` | Non-recursive normal map (preferred) |
| `:inoremap [key] [action]` | Non-recursive insert map |
| `:unmap [key]` | Remove mapping |
| `:mapclear` | Remove all mappings (dangerous) |
| `:command` | List ALL user commands — including plugin ones (`:Lazy`, `:Mason`, `:Yazi`, `:Telescope`, ...) |
| `:verbose [cmd]` | Show where a mapping was defined (e.g. `:verbose nmap <leader>k`) |

### Abbreviations

| Command | Action |
|---|---|
| `:ab [short] [long]` | Abbreviation in insert + command mode |
| `:iab [s] [l]` | Insert mode only abbreviation |
| `:cab [s] [l]` | Command mode only abbreviation |
| `:ab` | List all abbreviations |
| `:una [short]` | Remove abbreviation |

Examples: `:iab teh the` · `:iab @@ user@example.com` · `:iab #b #!/bin/bash`

### Autocommands

| Command | Action |
|---|---|
| `:autocmd [event] [pattern] [cmd]` | Define autocommand |
| `:autocmd` | List all autocommands |
| `:autocmd!` | Remove all autocommands |
| `:augroup [name]` | Define autocommand group |
| `:doautocmd [event]` | Manually trigger autocommand |

Common events: `BufWritePre` (before saving), `BufWritePost` (after saving), `BufEnter`/`BufLeave` (entering/leaving a buffer), `FileType` (filetype set), `VimEnter`/`VimLeave` (nvim start/exit), `InsertEnter`, `CursorHold` (cursor idle for `updatetime`).

Example — remove trailing spaces on save for C files:

```vim
:autocmd BufWritePre *.c :%s/\s\+$//e
```

### Diagnostics & Info

| Command | Action |
|---|---|
| `:version` | Show nvim version and compile info |
| `:verbose [cmd]` | Show where a cmd/option was last set (e.g. `:verbose set tabstop?`) |
| `:scriptnames` | List all sourced scripts in order |
| `:messages` | Show message history |
| `:history` | Show command history |
| `:history /` | Show search history |
| `:jumps` | Show jump list |
| `:changes` | Show change list |
| `:undolist` | Show undo tree branches |

### Undo Time Travel

| Command | Action |
|---|---|
| `:earlier 5m` | Restore the buffer to the state 5 minutes ago |
| `:earlier 3` | Undo 3 "undo states" (like `3u`) |
| `:later 10m` | Redo changes up to 10 minutes later |
| `:undolist` | Show the branches of the undo tree |

`:earlier`/`:later` work even across writes — genuine time machine, no plugin needed.

### Folds

| Command | Action |
|---|---|
| `:set foldmethod=indent` | Fold by indentation |
| `:set foldmethod=syntax` | Fold by syntax |
| `:set foldmethod=marker` | Fold by `{{{ }}}` markers |
| `:set foldmethod=expr` | Fold by expression (treesitter uses this) |
| `:set foldlevel=0` | Close all folds |
| `:set foldlevel=99` | Open all folds |
| `:mkview` | Save folds and view to file |
| `:loadview` | Restore saved folds |

### Sessions & Views

| Command | Action |
|---|---|
| `:mksession [file]` | Save current session (buffers, splits, etc.) |
| `:source [file]` | Restore session (also sources any vimscript/Lua file) |
| `:source %` | Re-source the current file |
| `:mkvimrc` | Save current settings to vimrc |
| `:mkview` | Save view (folds, cursor) for current file |
| `:loadview` | Restore view |

### Help (the manual, built-in)

| Command | Action |
|---|---|
| `:h [topic]` | Open help for a topic (e.g. `:h 'shiftwidth'` — note the quotes for options) |
| `:h index` | All default normal-mode keys, one page |
| `:h quickref` | The condensed overview of everything |
| `:h text-objects` | Every text object, listed |
| `:h regexp` | Vim regex dialect (`\v` very magic etc.) |
| `:h motion.txt` | All motions |
| `:helpgrep [pattern]` | Full-text search through all help files |
| `:Tutor` | The interactive 30-minute vim tutorial |

## Part 2 — Neovim only

### Lua

| Command | Action |
|---|---|
| `:lua [code]` | Execute Lua code inline |
| `:lua print("hello")` | Print from Lua |
| `:lua =vim.o.tabstop` | Inspect a value (`=` is shorthand for print) |
| `:luafile [file]` | Source a Lua file |
| `:source $MYVIMRC` | Reload your whole config (without restarting nvim) |

Useful inspection commands:

| Command | Action |
|---|---|
| `:lua =vim.api.nvim_list_bufs()` | List all buffer handles |
| `:lua =vim.fn.expand('%:p')` | Print full path of current file |
| `:lua =vim.bo.filetype` | Print filetype of current buffer |
| `:lua vim.print(vim.o)` | Pretty print all options |
| `:lua =vim.api.nvim_get_keymap('n')` | List all normal-mode mappings |

### Health & Inspect

| Command | Action |
|---|---|
| `:checkhealth` | Run full health check (LSP, providers...) |
| `:checkhealth [plugin]` | Check specific plugin health |
| `:checkhealth vim.deprecated` | See what deprecated APIs your plugins still use |
| `:Inspect` | Show highlight groups + treesitter node under cursor |
| `:InspectTree` | Show the live treesitter syntax tree of the buffer |

### Tips

- Use `:verbose set [option]?` to find where an option was set
- Use `:scriptnames` to debug slow startup or conflicting plugins
- `:g` and `:norm` together are incredibly powerful for bulk editing
- `:%!cmd` pipes your entire file through any unix command
- `:cdo` lets you apply a substitution to every file in the quickfix — e.g. after `:grep foo **/*.c` → `:cdo s/foo/bar/g | w`
- `:mksession` is the poor man's project manager — no plugin needed
- Ranges work with almost every command, not just `:s` and `:d`
- `:lua =` is the fastest way to inspect anything in your config
- `:InspectTree` shows exactly what treesitter sees — great for understanding highlighting or refactorings
- `:earlier 15m` saves you from disasters that undotree-style plugins overcomplicate
