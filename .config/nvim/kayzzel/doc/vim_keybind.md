# Neovim Native Keybinds — Cheatsheet

> From beginner to expert. Everything here is stock — no plugins needed.
> Your config's custom `<leader>` mappings live in `lua/config/keymaps.lua` and the plugin files.
> Search all mappings (custom + native) live with `<leader>k` (telescope keymaps picker).
>
> Two parts: **Part 1 — Vim** (works in classic Vim too) and **Part 2 — Neovim only**.

## Part 1 — Vim (works in classic Vim too)

### Modes

| Key | Action |
|---|---|
| `i` | Insert mode (before cursor) |
| `a` | Insert mode (after cursor) |
| `I` | Insert mode (beginning of line) |
| `A` | Insert mode (end of line) |
| `o` | Insert mode (new line below) |
| `O` | Insert mode (new line above) |
| `s` | Delete char under cursor and enter insert mode |
| `S` | Delete entire line and enter insert mode |
| `v` | Visual mode (character) |
| `V` | Visual mode (line) |
| `<C-v>` | Visual mode (block) |
| `R` | Replace mode (overwrite) |
| `r[char]` | Replace single char and return to normal |
| `:` | Command mode |
| `<Esc>` | Back to Normal mode |
| `<C-[>` | Same as `<Esc>` (alternative) |

### Basic Movement

| Key | Action |
|---|---|
| `h` `j` `k` `l` | Left / Down / Up / Right |
| `w` | Next word (start) |
| `W` | Next WORD (start, ignores punctuation) |
| `b` | Previous word (start) |
| `B` | Previous WORD (start, ignores punctuation) |
| `e` | Next word (end) |
| `E` | Next WORD (end, ignores punctuation) |
| `ge` | Previous word (end) |
| `0` | Start of line (column 0) |
| `^` | First non-blank character of line |
| `$` | End of line |
| `g_` | Last non-blank character of line |
| `gg` | First line of file |
| `G` | Last line of file |
| `[n]G` | Go to line n (e.g. `42G`) |
| `[n]%` | Go to n% of file (e.g. `50%` = middle) |
| `<C-d>` | Scroll half page down |
| `<C-u>` | Scroll half page up |
| `<C-f>` | Scroll full page down |
| `<C-b>` | Scroll full page up |
| `<C-e>` | Scroll one line down (cursor stays) |
| `<C-y>` | Scroll one line up (cursor stays) |

### Basic Editing

| Key | Action |
|---|---|
| `x` | Delete character under cursor |
| `X` | Delete character before cursor |
| `dd` | Delete (cut) current line |
| `D` | Delete from cursor to end of line |
| `yy` / `Y` | Yank (copy) current line |
| `p` | Paste after cursor / below line |
| `P` | Paste before cursor / above line |
| `u` | Undo |
| `<C-r>` | Redo |
| `U` | Undo all latest changes on one line (the forgotten sibling of `u`) |
| `.` | Repeat last change |
| `r[char]` | Replace character under cursor with `[char]` |
| `~` | Toggle case of character under cursor |
| `g~[motion]` | Toggle case over motion (e.g. `g~iw`) |
| `gu[motion]` | Lowercase over motion (e.g. `guiw`) |
| `gU[motion]` | Uppercase over motion (e.g. `gUiw`) |
| `J` | Join current line with line below |
| `gJ` | Join without adding space |

### Saving & Quitting

| Key | Action |
|---|---|
| `:w` | Save |
| `:q` | Quit |
| `:wq` / `:x` | Save and quit |
| `:q!` | Quit without saving |
| `:wa` | Save all buffers |
| `:qa` | Quit all buffers |
| `:qa!` | Quit all without saving |
| `ZZ` | Save and quit (normal mode shortcut) |
| `ZQ` | Quit without saving (normal mode shortcut) |

### Operators + Motions

Operators: `d` (delete), `y` (yank), `c` (change), `>` (indent), `<` (dedent) — combined with motions or text objects.

| Key | Action |
|---|---|
| `dw` | Delete to next word |
| `dW` | Delete to next WORD |
| `d$` / `D` | Delete to end of line |
| `d0` | Delete to start of line |
| `dgg` | Delete from cursor to start of file |
| `dG` | Delete from cursor to end of file |
| `diw` | Delete inner word |
| `daw` | Delete a word (includes surrounding space) |
| `di(` / `dib` | Delete inside parentheses |
| `da(` / `dab` | Delete including parentheses |
| `di"` | Delete inside double quotes |
| `da"` | Delete including double quotes |
| `di'` | Delete inside single quotes |
| `` di` `` | Delete inside backticks |
| `di{` / `diB` | Delete inside braces |
| `da{` / `daB` | Delete including braces |
| `di[` | Delete inside brackets |
| `da[` | Delete including brackets |
| `dit` | Delete inside HTML/XML tag |
| `dat` | Delete including HTML/XML tag |
| `dis` | Delete inner sentence |
| `dip` | Delete inner paragraph |
| `dap` | Delete a paragraph (includes blank line) |
| `ciw` | Change inner word |
| `ci(` | Change inside parentheses |
| `ci"` | Change inside quotes |
| `ci{` | Change inside braces |
| `cw` | Change to next word |
| `c$` / `C` | Change to end of line |
| `cc` | Change entire line |
| `yiw` | Yank inner word |
| `yi(` | Yank inside parentheses |
| `yy` | Yank current line |
| `y$` | Yank to end of line |
| `yG` | Yank to end of file |
| `>>` | Indent line |
| `<<` | Dedent line |
| `==` | Auto-indent current line |
| `=G` | Auto-indent from cursor to end of file |
| `gg=G` | Auto-indent entire file |
| `[n][op]` | Repeat operator n times (e.g. `3dd` = delete 3 lines) |

### Search & Replace

| Key | Action |
|---|---|
| `/pattern` | Search forward |
| `?pattern` | Search backward |
| `n` | Next match |
| `N` | Previous match |
| `*` | Search word under cursor (forward) |
| `#` | Search word under cursor (backward) |
| `g*` | Search partial word under cursor (forward) |
| `g#` | Search partial word under cursor (backward) |
| `%` | Jump to matching bracket / parenthesis |
| `:s/old/new/` | Replace first match on current line |
| `:s/old/new/g` | Replace all matches on current line |
| `:%s/old/new/g` | Replace all matches in file |
| `:%s/old/new/gc` | Replace all with confirmation |
| `:%s/old/new/gi` | Replace all, case insensitive |
| `:noh` | Clear search highlight |

### Visual Mode

| Key | Action |
|---|---|
| `v` | Start character selection |
| `V` | Start line selection |
| `<C-v>` | Start block selection |
| `o` | Move to other end of selection |
| `O` | Move to other corner (block mode) |
| `gv` | Reselect last visual selection |
| `d` (visual) | Delete selection |
| `y` (visual) | Yank selection |
| `c` (visual) | Change selection |
| `>` (visual) | Indent selection |
| `<` (visual) | Dedent selection |
| `=` (visual) | Auto-indent selection |
| `~` (visual) | Toggle case |
| `u` (visual) | Lowercase |
| `U` (visual) | Uppercase |
| `J` (visual) | Join selected lines |
| `:` (visual) | Command on selection (e.g. `:sort`) |
| `r[c]` (visual) | Replace all selected chars with `[c]` |
| `<C-v>` then `I` | Insert at start of each selected line |
| `<C-v>` then `A` | Append at end of each selected line |
| `<C-v>` then `c` | Change block (type, then `<Esc>` to apply) |
| `<C-v>` then `$A` | Append at true end of each selected line |

### Windows & Splits

| Key | Action |
|---|---|
| `:sp [file]` | Horizontal split |
| `:vsp [file]` | Vertical split |
| `<C-w>s` | Horizontal split (current file) |
| `<C-w>v` | Vertical split (current file) |
| `<C-w>n` | New empty horizontal split |
| `<C-w>h` / `j` / `k` / `l` | Move **cursor** between splits |
| `<C-w>H` / `J` / `K` / `L` | Move the **window** itself to far left/bottom/top/right |
| `<C-w>w` | Cycle through splits |
| `<C-w>p` | Jump to previous split |
| `<C-w>r` | Rotate splits clockwise |
| `<C-w>R` | Rotate splits counter-clockwise |
| `<C-w>x` | Swap current split with next |
| `<C-w>=` | Equalize split sizes |
| `<C-w>+` / `-` | Increase / decrease height |
| `<C-w>>` / `<` | Increase / decrease width |
| `<C-w>|` | Maximize width |
| `<C-w>_` | Maximize height |
| `<C-w>q` | Close current split |
| `<C-w>o` | Close all other splits |
| `<C-w>t` | Move current split to new tab |

### Tabs

| Key | Action |
|---|---|
| `:tabnew [file]` | Open file in new tab |
| `:tabn` / `gt` | Next tab |
| `:tabp` / `gT` | Previous tab |
| `[n]gt` | Go to tab n |
| `:tabclose` | Close current tab |
| `:tabo` | Close all other tabs |
| `:tabmove +1` | Move tab one position to the right |
| `:tabmove -1` | Move tab one position to the left |
| `:tabmove 0` | Move tab to first position |

### Buffers

| Key | Action |
|---|---|
| `:ls` / `:buffers` | List open buffers |
| `:b [n/name]` | Switch to buffer n or name |
| `:bn` | Next buffer |
| `:bp` | Previous buffer |
| `:bd` | Delete (close) buffer |
| `<C-^>` | Switch to alternate (last) buffer |

### Marks & Jumps

| Key | Action |
|---|---|
| `m[a-z]` | Set local mark |
| `m[A-Z]` | Set global mark (works across files) |
| `'[a-z]` | Jump to mark line |
| `` `[a-z] `` | Jump to mark exact position |
| `''` | Jump back to last jump position (line) |
| ` `` ` | Jump back to last jump position (exact) |
| `` `. `` | Jump to position of last change |
| `` `^ `` | Jump to position of last insert |
| `` `[ `` | Jump to start of last yank/change |
| `` `] `` | Jump to end of last yank/change |
| `` `< `` | Jump to start of last visual selection |
| `` `> `` | Jump to end of last visual selection |
| `<C-o>` | Jump backward in jump list |
| `<C-i>` | Jump forward in jump list |
| `:marks` | List all marks |
| `:jumps` | Show jump list |
| `:changes` | Show change list |
| `g;` | Jump to previous change position |
| `g,` | Jump to next change position |

### Folds

| Key | Action |
|---|---|
| `za` | Toggle fold under cursor |
| `zA` | Toggle fold recursively |
| `zo` | Open fold |
| `zO` | Open fold recursively |
| `zc` | Close fold |
| `zC` | Close fold recursively |
| `zR` | Open all folds in file |
| `zM` | Close all folds in file |
| `zr` | Reduce fold level by 1 (open one level) |
| `zm` | Increase fold level by 1 (close one level) |
| `zf[motion]` | Create fold (e.g. `zf5j` = fold next 5 lines) |
| `zd` | Delete fold under cursor |
| `zD` | Delete all folds in range |
| `zE` | Eliminate all folds in file |
| `[z` | Move to start of current open fold |
| `]z` | Move to end of current open fold |
| `zj` | Move to start of next fold |
| `zk` | Move to end of previous fold |

### Command Line Mode

(while typing a `:` command)

| Key | Action |
|---|---|
| `<Tab>` | Autocomplete command or filename |
| `<C-d>` | List all possible completions |
| `<Up>` / `<Down>` | Navigate command history |
| `<C-p>` / `<C-n>` | Navigate command history |
| `<C-r>[reg]` | Insert register content into command line |
| `<C-r><C-w>` | Insert word under cursor into command line |
| `<C-r><C-a>` | Insert WORD under cursor into command line |
| `<C-r>/` | Insert last search pattern into command line |
| `<C-f>` | Open command history in editable window |
| `<C-b>` | Move cursor to beginning of command |
| `<C-e>` | Move cursor to end of command |
| `<C-w>` | Delete word before cursor |
| `<C-u>` | Clear entire command line |
| `@:` | Repeat last command (normal mode) |
| `q:` | Open command history window (normal mode) |
| `q/` | Open search history window (normal mode) |
| `q?` | Open backward search history window |

### Command Line (basic)

| Key | Action |
|---|---|
| `:e [file]` | Open file |
| `:e!` | Reload current file (discard changes) |
| `:r [file]` | Read file and insert below cursor |
| `:r ![cmd]` | Insert output of shell command below cursor |
| `:[range]d` | Delete range of lines (e.g. `:5,10d`) |
| `:[range]y` | Yank range of lines |
| `:[range]m[line]` | Move range to after line (e.g. `:3,5m0`) |
| `:[range]co[line]` | Copy range to after line |
| `:sort` | Sort selected lines |
| `:sort!` | Sort in reverse |
| `:sort u` | Sort and remove duplicates |
| `:%!fmt` | Format entire file with external command |
| `:!cmd` | Run shell command |
| `!!` | Run shell command and replace current line with output |

### `[ ]` Bracket Motions

Pairs — `[` goes backward, `]` goes forward.

| Key | Action |
|---|---|
| `[[` / `]]` | Previous / next section (function, `{`) |
| `[]` / `][` | Previous / next end of section |
| `[(` / `])` | Previous / next unmatched `( )` |
| `[{` / `]}` | Previous / next unmatched `{ }` |
| `[m` / `]m` | Previous / next method start (Java/C++) |
| `[M` / `]M` | Previous / next method end |
| `[*` / `]*` | Previous / next start/end of `/* */` comment |
| `[/` / `]/` | Same as `[*` / `]*` |
| `[s` / `]s` | Previous / next spelling error (spell enabled) |
| `[q` / `]q` | Previous / next quickfix entry |

### `g` Commands

| Key | Action |
|---|---|
| `gd` | Go to local definition |
| `gD` | Go to global definition |
| `gf` | Go to file under cursor |
| `gF` | Go to file under cursor at line number |
| `gx` | Open URL under cursor in browser |
| `gg` | Go to first line |
| `G` | Go to last line |
| `g0` | Start of screen line (wrapped) |
| `g$` | End of screen line (wrapped) |
| `gj` | Move down by screen line (through wraps) |
| `gk` | Move up by screen line (through wraps) |
| `g~[motion]` | Toggle case over motion |
| `gu[motion]` | Lowercase over motion |
| `gU[motion]` | Uppercase over motion |
| `gq[motion]` | Format/wrap text to textwidth |
| `gw[motion]` | Format text without moving cursor |
| `gv` | Reselect last visual selection |
| `gi` | Enter insert at last insert position |
| `ga` | Show ASCII / Unicode value of char under cursor |
| `g<C-a>` | Increment sequence in visual block |
| `g<C-x>` | Decrement sequence in visual block |
| `g;` | Jump to previous change |
| `g,` | Jump to next change |
| `g&` | Repeat last substitute on all lines |
| `gn` | Select next search match (visual) |
| `gN` | Select previous search match (visual) |
| `gs` | Sleep (rarely used) |
| `g8` | Show hex value of UTF-8 char under cursor |

### `z` Commands

| Key | Action |
|---|---|
| `zt` | Scroll so cursor is at top of screen |
| `zz` | Scroll so cursor is at middle of screen |
| `zb` | Scroll so cursor is at bottom of screen |
| `z<Enter>` | Same as `zt` but cursor moves to first non-blank |
| `za`/`zA` | Toggle fold / recursively |
| `zo`/`zO` | Open fold / recursively |
| `zc`/`zC` | Close fold / recursively |
| `zR` | Open all folds |
| `zM` | Close all folds |
| `zr`/`zm` | Open/close one fold level globally |
| `zf[motion]` | Create fold |
| `zd`/`zD`/`zE` | Delete fold / recursively / all |
| `zg` | Add word under cursor to dictionary |
| `zG` | Temporarily add word (session only) |
| `zw` | Mark word as wrong |
| `zW` | Temporarily mark word as wrong |
| `z=` | Suggest spelling corrections |
| `zu`/`zU` | Undo `zg`/`zw` |
| `zh`/`zl` | Scroll screen left / right (no-wrap mode) |
| `zH`/`zL` | Scroll half screen left / right |
| `ze`/`zs` | Scroll so cursor is at right / left of screen |

### Netrw (built-in file explorer)

> NOTE: this config replaces netrw with **yazi** for file browsing
> (`<leader>md`, and opening a directory launches yazi). Kept for reference.

| Key | Action |
|---|---|
| `:Ex` / `:Explore` | Open netrw in current window |
| `:Sex` / `:Sexplore` | Open netrw in horizontal split |
| `:Vex` / `:Vexplore` | Open netrw in vertical split |
| `:Tex` / `:Texplore` | Open netrw in new tab |
| `:e .` | Open netrw at current directory |
| `<Enter>` (netrw) | Open file or directory |
| `-` (netrw) | Go up one directory |
| `%` (netrw) | Create new file |
| `d` (netrw) | Create new directory |
| `D` (netrw) | Delete file or directory |
| `R` (netrw) | Rename file |
| `i` (netrw) | Toggle listing style (thin/long/wide/tree) |
| `s` (netrw) | Change sort order |
| `gh` (netrw) | Toggle hidden files |
| `<C-l>` (netrw) | Refresh listing |
| `p` (netrw) | Preview file |
| `o` (netrw) | Open in horizontal split |
| `v` (netrw) | Open in vertical split |
| `t` (netrw) | Open in new tab |
| `x` (netrw) | Open with system default app |
| `mb` / `gb` / `qb` | Bookmark dir / jump to bookmark / list bookmarks |

### Registers

| Key | Action |
|---|---|
| `"[a-z]y` | Yank into register a-z (e.g. `"ayy`) |
| `"[a-z]p` | Paste from register a-z (e.g. `"ap`) |
| `"[A-Z]y` | Append yank to register (e.g. `"Ayy`) |
| `"+y` | Yank to system clipboard |
| `"+p` | Paste from system clipboard |
| `"*y` | Yank to selection clipboard (Linux middle-click) |
| `"0p` | Paste last yank (not affected by delete) |
| `"_d` | Delete to black hole register (no clipboard pollution) |
| `":p` | Paste last command |
| `"/p` | Paste last search pattern |
| `".p` | Paste last inserted text |
| `"%p` | Paste current filename |
| `"#p` | Paste alternate filename |
| `:reg` | List all registers and their content |
| `<C-r>[reg]` | Paste register in insert/command mode (e.g. `<C-r>a`) |
| `<C-r><C-r>[reg]` | Paste register literally (no auto-indent) |

### Macros

| Key | Action |
|---|---|
| `q[a-z]` | Start recording macro into register |
| `q` | Stop recording |
| `@[a-z]` | Play macro |
| `@@` | Replay last macro |
| `[n]@[a-z]` | Play macro n times (e.g. `10@a`) |
| `:norm @a` | Apply macro to each line in a visual selection |

Editing a macro: `"ap` → edit it → `"ayy` to save it back into register a.

### Advanced Movement

| Key | Action |
|---|---|
| `f[char]` | Jump forward to char on line |
| `F[char]` | Jump backward to char on line |
| `t[char]` | Jump forward until char (stops before it) |
| `T[char]` | Jump backward until char (stops after it) |
| `;` | Repeat last f/F/t/T in same direction |
| `,` | Repeat last f/F/t/T in opposite direction |
| `H` | Move cursor to top of screen |
| `M` | Move cursor to middle of screen |
| `L` | Move cursor to bottom of screen |
| `zt` / `zz` / `zb` | Scroll cursor line to top / middle / bottom |
| `(` | Jump to start of previous sentence |
| `)` | Jump to start of next sentence |
| `{` | Jump to previous empty line / paragraph |
| `}` | Jump to next empty line / paragraph |
| `gd` | Go to local definition |
| `gD` | Go to global definition |
| `gf` | Go to file under cursor |
| `K` | Show man page / docs for word under cursor |

### Quickfix & Location List

| Key | Action |
|---|---|
| `:copen` | Open quickfix list |
| `:cclose` | Close quickfix list |
| `:cn` | Next quickfix entry |
| `:cp` | Previous quickfix entry |
| `:cc [n]` | Jump to entry n |
| `:lopen` | Open location list |
| `:lclose` | Close location list |
| `:ln` | Next location entry |
| `:lp` | Previous location entry |

### Global Command

| Key | Action |
|---|---|
| `:g/pattern/cmd` | Run cmd on every line matching pattern |
| `:g/pattern/d` | Delete all lines matching pattern |
| `:g!/pattern/d` | Delete all lines NOT matching pattern |
| `:g/pattern/y A` | Append all matching lines to register a |
| `:g/^$/d` | Delete all empty lines |
| `:g/pattern/norm @a` | Apply macro to all matching lines |

### Insert Mode Tricks

| Key | Action |
|---|---|
| `<C-w>` | Delete word before cursor |
| `<C-u>` | Delete to start of line |
| `<C-h>` | Delete character before cursor (backspace) |
| `<C-j>` | Insert newline (same as `<Enter>`) |
| `<C-t>` | Indent current line |
| `<C-d>` | Dedent current line |
| `<C-o>` | Execute one normal mode command then return to insert |
| `<C-r>[reg]` | Paste from register without leaving insert mode |
| `<C-r>=` | Insert result of expression (e.g. `<C-r>=2+2` → `4`) |
| `<C-n>` | Autocomplete next (native) |
| `<C-p>` | Autocomplete previous (native) |
| `<C-x><C-f>` | Autocomplete file paths |
| `<C-x><C-l>` | Autocomplete whole lines |
| `<C-x><C-n>` | Autocomplete from current buffer keywords |
| `<C-x><C-]>` | Autocomplete from tags |
| `<C-x><C-o>` | Omni-completion (language aware, needs filetype) |
| `<C-a>` | Insert last inserted text again |
| `<C-e>` | Cancel completion / insert char below cursor |
| `<C-y>` | Accept completion / insert char above cursor |
| `<C-g>u` | Break the undo sequence here — makes a long insert splittable with `u` |

### Misc Power Features

| Key | Action |
|---|---|
| `<C-a>` | Increment number under cursor |
| `<C-x>` | Decrement number under cursor |
| `g<C-a>` | Increment sequence (in visual block) |
| `g<C-x>` | Decrement sequence (in visual block) |
| `ga` | Show ASCII / Unicode value of character under cursor |
| `g8` | Show hex value of UTF-8 character under cursor |
| `gq[motion]` | Format/wrap text (e.g. `gqq` = wrap current line) |
| `gw[motion]` | Format text, cursor stays in place |
| `J` | Join current line with line below |
| `gJ` | Join without adding space |
| `xp` | Swap current char with next (transpose) |
| `Xp` | Swap current char with previous |
| `ddp` | Swap current line with next |
| `ddkP` | Swap current line with previous |
| `]p` / `[p` | Paste line and re-indent it to match surroundings |
| `gp` / `gP` | Paste and leave cursor AFTER the pasted text (great for pasting then moving on) |
| `]s` / `[s` | Next / previous spelling error |
| `z=` | Suggest spelling corrections |
| `zg` | Add word to dictionary |
| `zw` | Mark word as misspelled |
| `&` | Repeat last substitute (current line) |
| `g&` | Repeat last substitute on all lines |
| `:ab [s][l]` | Set abbreviation (e.g. `:ab teh the`) |

## Part 2 — Neovim only

### Terminal Mode

Neovim's built-in terminal emulator. `<C-\><C-n>` is THE key to remember:
it's how you escape terminal mode back to normal mode.

| Key | Action |
|---|---|
| `:terminal` | Open terminal in current window |
| `:sp \| terminal` | Open terminal in horizontal split |
| `:vsp \| terminal` | Open terminal in vertical split |
| `<C-\><C-n>` | Exit terminal mode → Normal mode |
| `i` / `a` | Re-enter terminal mode from normal mode |
| `<C-w>h/j/k/l` | Move to another split (from terminal mode) |
| `<C-w>N` | Enter normal mode in terminal (alternative) |

### LSP (Neovim 0.11+ defaults)

These work when a language server is attached to the buffer (this config: lua_ls, pyright, ts_ls, clangd, rust_analyzer). Note: `gd`/`grr`/`gi`/`gra`/`grn` are wired to telescope pickers in `lua/plugins/lsp.lua`.

| Key | Action |
|---|---|
| `gd` | Go to definition |
| `gD` | Go to declaration |
| `K` | Hover documentation |
| `grr` | List references |
| `grn` | Rename symbol |
| `gra` | Code action |
| `gri` | Go to implementation |
| `gO` | Document symbols outline (structure of current file) |
| `[d` / `]d` | Previous / next diagnostic |
| `[e` / `]e` | Previous / next error |

### Tips

- Almost every operator accepts a count: `3dw`, `5j`, `2yy`, `10>>`
- Combine registers + macros for powerful batch editing
- Use `:norm[al]` to apply normal mode commands to a range of lines
- `.` (dot) is your best friend — design edits to be repeatable
- `<C-v>` block mode + `I`/`A` lets you edit multiple lines at once
- Think in text objects: `iw` `i(` `i"` `i{` `it` — not character by character
- `gn` selects the next search match — combine with `c` for fast refactor
- `gv` + `.` — repeat your last change on the entire last selection
- `<C-r>=` in insert mode turns vim into a calculator
- `<C-r><C-w>` in command mode pastes the word under cursor — great for `:%s/`
- `q:` opens an editable command history — edit and run old commands
- `<C-^>` is the fastest way to alternate between two files
- `"_` (black hole register) lets you delete without overwriting clipboard
- Editing a macro: `"ap` → fix it → `"ayy` to save it back
