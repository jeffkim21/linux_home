let g:gutentags_project_root=['.gutentags']
let g:gutentags_modules=['ctags','gtags_cscope']
set statusline+=${gutentags#statusline()}
let g:gutentags_cache_dir='.gutentags_db'
let g:gutentags_file_list_command=
	\"
	\ find . -type f 
	\ -name '*.cpp' -or
	\ -name '*.c' -or
	\ -name '*.cxx' -or
	\ -name '*.h' -or
	\ -name '*.hpp' | 
	\ grep -v build |
	\ grep -v cmake |
	\ grep -v cache |
	\ grep -v tags |
	\ tee files.txt
	\"
"nmap <C-\>s :cs find s <C-R>=expand("<cword>")<CR><CR>
"nmap <C-\>g :cs find g <C-R>=expand("<cword>")<CR><CR>
"nmap <C-\>c :cs find c <C-R>=expand("<cword>")<CR><CR>
"nmap <C-\>t :cs find t <C-R>=expand("<cword>")<CR><CR>
"nmap <C-\>e :cs find e <C-R>=expand("<cword>")<CR><CR>
"nmap <C-\>f :cs find f <C-R>=expand("<cfile>")<CR><CR>
"nmap <C-\>i :cs find i ^<C-R>=expand("<cfile>")<CR>$<CR>
"nmap <C-\>d :cs find d <C-R>=expand("<cword>")<CR><CR>
"nmap <C-\>a :cs find a <C-R>=expand("<cword>")<CR><CR>

nmap <C-\> :cs find c <C-R>=expand("<cword>")<CR><CR>
