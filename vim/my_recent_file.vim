let s:selections = []
let s:recent_files = []

function! OpenRecentFilesPopup()
  " Gather the list of recent files from v:oldfiles
  let s:recent_files = filter(v:oldfiles,'v:val !~ "doc"')

  " If there are no recent files, show a message and exit
  if empty(s:recent_files)
    echo "No recent files available."
    return
  endif

  " Initialize selection markers
  let s:selections = repeat([0], len(s:recent_files))

  " Display the popup menu
  call s:RenderPopupMenu()
endfunction

function! s:RenderPopupMenu()
  " Build menu items with markers
  let menu_items = []
  for i in range(len(s:recent_files))
    let prefix = s:selections[i] ? '[x] ' : '[ ] '
    call add(menu_items, prefix . fnamemodify(s:recent_files[i], ':~'))
  endfor

  " Show the popup menu
  call popup_menu(menu_items, #{
        \ title:'Recent Files',
        \ callback:'s:RecentFilesMenuCallback'
        \ })
endfunction

function! s:KeyHandler(id, key)
	echom a:id
	echom a:key
	return popup_filter_menu(a:id, a:key)
endfunction

"function! s:PopupKeyHandler(id, key)
"  let current_line = popup_getpos(a:id).line - 1
"
"  if a:key == "\<Space>" " Toggle selection
"    let s:selections[current_line] = !s:selections[current_line]
"    let prefix = s:selections[current_line] ? '[x]' : '[ ]'
"	call popup_settext(a:id, prefix . fnamemodify(s:recent_files[l:current_line], ':~'))
"    return v:true " Consume the key
"  elseif a:key == "\<cr>" " Finalize selection
"    call s:OpenSelectedFiles()
"    call popup_close(a:id)
"    return v:true " Consume the key
"  elseif a:key == "\<esc>" " Cancel selection
"    call popup_close(a:id)
"    return v:true " Consume the key
"  endif
"
"  return v:false " Allow default behavior for other keys
"endfunction

function! s:RecentFilesMenuCallback(id, index)
  execute 'edit' fnameescape(s:recent_files[a:index-1])
  call popup_clear()
endfunction

function! s:OpenSelectedFiles()
  " Open all selected files
  for i in range(len(s:selections))
    if s:selections[i]
      execute 'edit' fnameescape(s:recent_files[i])
    endif
  endfor
endfunction

" Map a key to open the popup menu
nnoremap <silent> <c-o> :call OpenRecentFilesPopup()<CR>
