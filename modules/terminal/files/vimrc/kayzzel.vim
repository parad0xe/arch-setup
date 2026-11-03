" file
set noswapfile

set undofile
set undodir=~/.local/share/vim/undo/
if !isdirectory(expand(&undodir))
    call mkdir(expand(&undodir), "p")
endif
set undolevels=500

" lines
set number
set relativenumber
set cursorline

" tabs & indent
set tabstop=4
set shiftwidth=4
set autoindent
set backspace=indent,eol,start

" keep cursor centered vertically while scrolling
set scrolloff=10

" Leader key
let mapleader = " "

" Normal
nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>Q :q!<CR>
nnoremap <leader>x :x<CR>

nnoremap <leader><space> :Ex<CR>

nnoremap <C-k> V:move '<-2<CR>gv-gv<Esc>
nnoremap <C-j> V:move '>+1<CR>gv-gv<Esc>
xnoremap <C-k> :move '<-2<CR>gv-gv
xnoremap <C-j> :move '>+1<CR>gv-gv

nnoremap <C-u> <C-u>zz
nnoremap <C-d> <C-d>zz

" search terms stay centered
nnoremap n nzzzv
nnoremap N Nzzzv

" keep visual selection after indenting (instead of losing it)
vnoremap < <gv
vnoremap > >gv

" move around the tabs
map <leader>tn :tabnew<cr>
map <leader>to :tabonly<cr>
map <leader>tc :tabclose<cr>
map <leader>tm :tabmove
map <leader>t<leader> :tabnext<cr>

" Changed the color
syntax on

highlight LineNr ctermfg=DarkGrey ctermbg=NONE
highlight CursorLineNr ctermfg=DarkMagenta ctermbg=NONE
