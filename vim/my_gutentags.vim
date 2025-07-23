let g:gutentags_project_root=['.root']
let g:gutentags_modules=['ctags','gtags_cscope']
set statusline+=${gutentags#statusline()}
let g:gutentags_cache_dir='~/local/tags'
let g:gutentags_plus_switch=1
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
	\ grep -v tags
	\"
