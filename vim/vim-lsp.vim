"if executable('clangd')
"    " pip install python-lsp-server
"    au User lsp_setup call lsp#register_server({
"        \ 'name': 'clangd',
"        \ 'cmd': {server_info->['clangd']},
"        \ 'allowlist': ['cpp','c','objc','objcpp'],
"        \ })
"endif
"
"function! s:on_lsp_buffer_enabled() abort
"    setlocal omnifunc=lsp#complete
"    setlocal signcolumn=yes
"    if exists('+tagfunc') | setlocal tagfunc=lsp#tagfunc | endif
"    nmap <buffer> gd <plug>(lsp-definition)
"    nmap <buffer> gs <plug>(lsp-document-symbol-search)
"    nmap <buffer> gS <plug>(lsp-workspace-symbol-search)
"    nmap <buffer> gr <plug>(lsp-references)
"    nmap <buffer> gi <plug>(lsp-implementation)
"    nmap <buffer> gt <plug>(lsp-type-definition)
"    nmap <buffer> <leader>rn <plug>(lsp-rename)
"    nmap <buffer> [g <plug>(lsp-previous-diagnostic)
"    nmap <buffer> ]g <plug>(lsp-next-diagnostic)
"    nmap <buffer> K <plug>(lsp-hover)
"    nnoremap <buffer> <expr><c-f> lsp#scroll(+4)
"    nnoremap <buffer> <expr><c-d> lsp#scroll(-4)
"
"    let g:lsp_format_sync_timeout = 1000
"    autocmd! BufWritePre *.c,*.cpp call execute('LspDocumentFormatSync')
"    
"    " refer to doc to add more commands
"endfunction
"
"augroup lsp_install
"    au!
"    " call s:on_lsp_buffer_enabled only for languages that has the server registered.
"    autocmd User lsp_buffer_enabled call s:on_lsp_buffer_enabled()
"augroup END
au User lsp_setup call lsp#register_server({
      \ 'name': 'clangd',
      \ 'cmd': ['clangd'],
      \ 'whitelist': ['c', 'cpp', 'objc', 'objcpp'],
      \ })

" 자동완성에 omnicompletion 사용
set omnifunc=lsp#complete

" 오류 위치 자동 업데이트
"autocmd BufWritePost *.c,*.cpp LspDocumentDiagnostics

" 단축키 매핑
nmap <silent> gd <Plug>(lsp-definition)
nmap <silent> gr <Plug>(lsp-references)
nmap <silent> gi <Plug>(lsp-implementation)
nmap <silent> K  <Plug>(lsp-hover)

let g:lsp_diagnostics_enabled = 0
let g:lsp_document_highlight_enabled = 0
let g:lsp_hover_auto=0
let g:lsp_signature_help_enabled=0
let g:lsp_format_sync_timeout=0
let g:lsp_log_verbose=0
