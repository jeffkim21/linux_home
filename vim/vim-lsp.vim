"==============================
" vim-lsp 설정
"==============================
" clangd 언어 서버 등록 (자동 설정됨, 명시적으로도 가능)
au User lsp_setup call lsp#register_server({
      \ 'name': 'clangd',
      \ 'cmd': ['clangd'],
      \ 'whitelist': ['c', 'cpp', 'objc', 'objcpp'],
      \ })

" 파일 저장 시 자동 포맷
" autocmd BufWritePre *.c,*.cpp call lsp#format_sync()

" 상태 라인에 LSP 상태 표시
set statusline+=%{lsp#get_server_status()}

"==============================
" 자동완성 설정
"==============================
set completeopt=menuone,noinsert,noselect
let g:lsp_completion_documentation_enabled = 1
autocmd FileType c,cpp setlocal omnifunc=lsp#complete

"==============================
" 키 매핑 (LSP 기능 단축키)
"==============================
nnoremap <silent> gd :LspDefinition<CR>
nnoremap <silent> gr :LspReferences<CR>
nnoremap <silent> K  :LspHover<CR>
nnoremap <silent> gi :LspImplementation<CR>
nnoremap <silent> gs :LspDocumentSymbol<CR>
nnoremap <silent> gn :LspNextDiagnostic<CR>
nnoremap <silent> gp :LspPreviousDiagnostic<CR>
nnoremap <silent> gf :LspDocumentFormat<CR>
nnoremap <silent> ga :LspCodeAction<CR>

let g:lsp_diagnostics_enabled = 0
let g:lsp_document_highlight_enabled = 0
let g:lsp_hover_auto=0
let g:lsp_signature_help_enabled=0
let g:lsp_format_sync_timeout=0
let g:lsp_log_verbose=0
