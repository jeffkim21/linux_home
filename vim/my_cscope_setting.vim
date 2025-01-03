set cst

silent cs kill -1

if filereadable("./cscope.out")
	silent cs add ./cscope.out
elseif filereadable("../cscope.out")
	silent cs add ../cscope.out
elseif filereadable("../../cscope.out")
	silent cs add ../../cscope.out
elseif filereadable("../../../cscope.out")
	silent cs add ../../../cscope.out
endif

nmap <C-\>s :cs find s <C-R>=expand("<cword>")<CR><CR>
nmap <C-\>g :cs find g <C-R>=expand("<cword>")<CR><CR>
nmap <C-\>c :cs find c <C-R>=expand("<cword>")<CR><CR>
nmap <C-\>t :cs find t <C-R>=expand("<cword>")<CR><CR>
nmap <C-\>e :cs find e <C-R>=expand("<cword>")<CR><CR>
nmap <C-\>f :cs find f <C-R>=expand("<cfile>")<CR><CR>
nmap <C-\>i :cs find i ^<C-R>=expand("<cfile>")<CR>$<CR>
nmap <C-\>d :cs find d <C-R>=expand("<cword>")<CR><CR>
nmap <C-\>a :cs find a <C-R>=expand("<cword>")<CR><CR>

if filereadable("./tags")
	set tags+=./tags
elseif filereadable("../tags")
	set tags+=../tags
elseif filereadable("../../tags")
	set tags+=../../tags
elseif filereadable("../../../tags")
	set tags+=../../../tags
endif
