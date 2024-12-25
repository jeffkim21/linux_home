nnoremap <F2> :Lexplore<cr>
nnoremap <F3> :vert term<cr>
nnoremap <F4> :call WinClose()<cr>

function! WinClose()
	winc l
	winc o
endfunction

augroup helpwin
	au!
	au FileType help winc H
	au FileType quickfix winc H
augroup end
