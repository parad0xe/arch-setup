call plug#begin()

" navigation
Plug 'nvim-tree/nvim-web-devicons'
Plug 'nvim-tree/nvim-tree.lua'
Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-telescope/telescope.nvim', { 'tag': 'v0.2.2' }
Plug 'nxhung2304/lastplace.nvim'

" code
Plug 'kkoomen/vim-doge', { 'do': { -> doge#install() } }
Plug 'mfussenegger/nvim-lint'
Plug 'rmagatti/logger.nvim'
Plug 'rmagatti/goto-preview'
Plug 'nvim-treesitter/nvim-treesitter'
Plug 'camAtGitHub/pydochide.nvim'
Plug 'hardyrafael17/norminette42.nvim'
"Plug 'cacharle/c_formatter_42.vim'
Plug 'folke/flash.nvim'

" code -> lsp
Plug 'mason-org/mason.nvim'
Plug 'WhoIsSethDaniel/mason-tool-installer.nvim'
Plug 'mason-org/mason-lspconfig.nvim'
Plug 'neovim/nvim-lspconfig'

" code -> completion
Plug 'nvim-mini/mini.nvim'

" code -> format
Plug 'stevearc/conform.nvim'

" tools
Plug 'kdheepak/lazygit.nvim'
Plug 'tpope/vim-surround'
Plug 'iamcco/markdown-preview.nvim', { 'do': { -> mkdp#util#install() }, 'for': ['markdown', 'vim-plug']}
Plug 'akinsho/toggleterm.nvim', {'tag' : '*'}

" appearance
Plug 'folke/tokyonight.nvim'
Plug 'xiyaowong/transparent.nvim'
Plug 'tamton-aquib/staline.nvim'
Plug 'sphamba/smear-cursor.nvim'
Plug 'rachartier/tiny-glimmer.nvim'

call plug#end()

syntax on
set nu
set colorcolumn=79
set tabstop=4
set shiftwidth=4
set smartindent
set autoindent

set undofile
set undodir=~/.local/share/nvim/undo/
set undolevels=300

function! CHeader()
	let header = expand("%:t:r")
	call append(0,"#ifndef ".toupper(header)."_H")
	call append(1,"# define ".toupper(header)."_H")
	call append(2,"")
	call append(3,"")
	call append(4,"")
	call append(5,"#endif")
	call cursor(4, 0)
endfunction

function! CMain()
	call append(0,"#include <>")
	call append(1,"")
	call append(2,"int	main(int argc, char *argv[])")
	call append(3,"{")
	call append(4,"\t")
	call append(5,"\treturn (0);")
	call append(6,"}")
	call cursor(5, 0)
endfunction

function! Main()
    call append(1, "")
    call append(2, "def main() -> None:")
    call append(3, "    pass")
    call append(4, "")
    call append(5, "")
    call append(6, "if __name__ == '__main__':")
    call append(7, "	main()")
	call cursor(4, 9)
endfunction

command! -nargs=0 CHeader call CHeader()
command! -nargs=0 CMain call CMain()
command! -nargs=0 Main call Main()

source ~/.config/nvim/config.lua

let g:doge_doc_standard_python = 'google'
