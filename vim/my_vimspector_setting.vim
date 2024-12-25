let g:vimspector_enable_mappings = "HUMAN"
syntax enable
filetype plugin indent on

"nnoremap <F5> :call vimspector#Launch()<CR>
"nnoremap <F6> :call vimspector#StepOut()<CR>
"nnoremap <F7> :call vimspector#StepInto()<CR>
"nnoremap <F8> :call vimspector#StepOver()<CR>

"nnoremap <F9> :call vimspector#ToggleBreakpoint()<CR>
"nnoremap <F10> :call vimspector#Reset()<CR>
"nnoremap <F11> :call vimspector#Restart()<CR>

nmap <F5>		<Plug>VimspectorContinue
nmap <S-F5>		<Plug>VimspectorStop
nmap <F6>		<Plug>VimspectorPause
nmap <F8>		<Plug>VimspecotrJumpToNextBreakpoint
nmap <S-F8>		<Plug>VimspectorJumpToPreviousBreakPoint
nmap <F9>		<Plug>VimspectorToggleBreakPoint
nmap <S-F9>		<Plug>VimspectorAddFunctionPreakpoint
nmap <F10>		<Plug>VimspectorRunToCursor
nmap <F11>		<Plug>VimspectorStepInto
nmap <S-F11>	<Plug>VimspectorStepOut
nmap <F12>		<Plug>VimspectorStepOver
	
