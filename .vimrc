syn on
set autoindent
set noerrorbells
set visualbell
if has('autocmd')
    autocmd GUIEnter * set vb t_vb=
    filetype indent on
    autocmd FileType python set ts=4 sw=4 et
endif
set hlsearch
set cindent
set guifont=Monospace\ 9
