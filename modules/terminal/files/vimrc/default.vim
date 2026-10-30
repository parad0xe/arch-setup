syntax on
filetype plugin indent on

set number
set tabstop=4
set shiftwidth=4
set expandtab
set autoindent
set backspace=indent,eol,start

set incsearch
set hlsearch
set ignorecase
set smartcase

set undofile
set undodir=~/.local/share/vim/undo/
if !isdirectory(expand(&undodir))
    call mkdir(expand(&undodir), "p")
endif
