
" Make sure line-continuations won't cause any problem. This will be restored at the end
let s:save_cpo = &cpo
set cpo&vim

" Initizalization {{{

if !exists('s:myBufNum')
  let s:myBufNum = -1
  let s:funcBufNum = -1
  let s:bpCounters = {}
  
  let g:BreakPts_title = "BreakPts"
  let g:BreakPts_locals_title = "BreakPts_Locals"
  let g:BreakPts_backtrace_title = "BreakPts_Backtrace"
  let s:BreakListing_title = "BreakPts Listing"
  let s:opMode = ""
  let s:remoteServName = '.'
  let s:curLineInCntxt = '' " Current line for context.
  let s:auloadedSids = {} " A cache keyed by their autoload prefix (without #).
  let s:autoCmd = ""
  let s:autoCmdLevel = 1
endif

let breakpts#BM_SCRIPT = 'script'
let breakpts#BM_SCRIPTS = 'scripts'
let breakpts#BM_FUNCTION = 'function'
let breakpts#BM_FUNCTIONS = 'functions'
let breakpts#BM_BRKPTS = 'breakpts'

let s:cmd_scripts = 'script'
let s:cmd_functions = 'function'
let s:cmd_breakpts = 'breaklist'
let s:header{breakpts#BM_SCRIPTS} = 'Scripts:'
let s:header{breakpts#BM_FUNCTIONS} = 'Functions:'
let s:header{breakpts#BM_BRKPTS} = 'Breakpoints:'

if has("patch-7.4.879")
  let s:FUNC_NAME_PAT = '\%(<SNR>\d\+_\)\?\k\+\%(\[\d\+\]\)\?' | lockvar s:FUNC_NAME_PAT
else
  let s:FUNC_NAME_PAT = '\%(<SNR>\d\+_\)\?\k\+' | lockvar s:FUNC_NAME_PAT
endif

function! s:MyScriptId()
  map <SID>xx <SID>xx
  let s:sid = maparg("<SID>xx")
  unmap <SID>xx
  return substitute(s:sid, "xx$", "", "")
endfunction
let s:myScriptId = s:MyScriptId()
delfunction s:MyScriptId

if has("signs")
  sign define EmptyBreakPt
  if has('multi_byte') && has('unix') && &encoding == 'utf-8' &&
      \ (empty(&termencoding) || &termencoding == 'utf-8')
    sign define VimBreakPt linehl=BreakPtsBreakLine text=✔ texthl=BreakPtsBreakLine
    sign define VimBreakDbgCur text=➤
  else
    sign define VimBreakPt linehl=BreakPtsBreakLine text=\/ texthl=BreakPtsBreakLine
    sign define VimBreakDbgCur text=->
  endif
endif

if !exists('g:brkpts_iconchars')
  if has('multi_byte') && has('unix') && &encoding == 'utf-8' &&
      \ (empty(&termencoding) || &termencoding == 'utf-8')
    let g:brkpts_iconchars = ['▶', '▼']
  else
    let g:brkpts_iconchars = ['+', '-']
  endif
endif

let s:icon_closed = g:brkpts_iconchars[0]
let s:icon_open   = g:brkpts_iconchars[1]

let s:brkpts_locals = { 
    \ "locals" : {}
    \ , "arguments" : {}
    \ , "expressions" : {}
    \ , "loaded" : 0
    \ }

function! s:brkpts_locals.locals.format(name)
  return a:name
endfunction

function! s:brkpts_locals.arguments.format(name)
  return "a:" . a:name
endfunction

function! s:brkpts_locals.expressions.format(name)
  return a:name
endfunction

function! s:brkpts_locals.arguments.parse(lines)
  let func_def = a:lines[0]
  let str_arguments = substitute(func_def, '.*(\(.*\)).*', '\1', '')
  if str_arguments == ""
    return []
  endif
  let arguments = split(str_arguments, '\s*,\s*')
  if arguments[len(arguments)-1] == "..."
    call remove(arguments, len(arguments)-1) 
    call add(arguments, '000')
    let pos_arg = 0
    let maxargs = s:EvalExpr('a:0')
    while pos_arg <= maxargs
      call add(arguments, pos_arg) 
      let pos_arg += 1
    endwhile
  endif
  if func_def =~ "range$"
    call add(arguments, "firstline")
    call add(arguments, "lastline")
  endif
  return arguments
endfunction

function! s:brkpts_locals.locals.parse(lines)
  let assignments = filter(copy(a:lines), "v:val =~ '^\\d\\+\\s*\\<\\(let\\|for\\)\\>'")
  let new_assignments = []
  for pos in range(0, len(assignments) - 1)
    let assignment = get(assignments, pos)
    if assignment =~ 'let\s\+\[.\+\]' 
      let vars = split(substitute(assignment, '^\d\+\s*let\s\+\[\(.\{-}\)\].*', '\1', ''), '\s*,\s*') 
      for var in vars
        call add(new_assignments, "let " . var)
      endfor
    elseif assignment =~ '^\d\+\s*for\s\+.*\s\+in'
      let var = substitute(assignment, '^\d\+\s*for\s\+\(.\{-}\)\s\+in.*', '\1', '') 
      call add(new_assignments, "let " . var)
    else
      call add(new_assignments, assignment)
    endif
  endfor
  return uniq(sort(map(new_assignments, "substitute(v:val, '^.\\{-}let\\s\\{-}\\([^[:space:]]\\+\\).*','\\1','')")))
endfunction

function s:brkpts_locals.expressions.parse(lines)
  return []
endfunction

function! s:PrintLocals() 
  if !s:brkpts_locals.loaded
    call s:PopulateLocals()
  endif

  let bufLocalNr = bufwinnr(g:BreakPts_locals_title)  
  if bufLocalNr == -1
    exec "vertical rightbelow new " . g:BreakPts_locals_title
    call breakpts#SetupBuf()
    let s:opMode = 'user'
  elseif bufwinnr("%") != bufLocalNr
    noautocmd exec bufLocalNr . 'wincmd w'
  endif
 
  silent %delete_

  for key in keys(s:brkpts_locals)
    let group = s:brkpts_locals[key]
    if type(group) != type({}) || !has_key(group, "variables")
      unlet group
      continue
    endif
    if group.isFolded
      let foldmarker = s:icon_closed
    else
      let foldmarker = s:icon_open
    endif

    silent put =foldmarker . ' ' . key
    let group.line = line(".")
    if !group.isFolded
      for variable in group.variables
        try
          let value = <SID>GetRemoteExpr(group.format(variable.name), variable.level, 6)
        catch
          let value = "(undefined)"
        endtry
        let varline = line('.') + 1
        silent put ='   ' . variable.name . ': ' . value
        let variable.line = varline
      endfor
    endif
    unlet group
  endfor

  let s:ics = escape(join(g:brkpts_iconchars, ''), ']^\-')
  let s:pattern = '\S\@<![' . s:ics . ']\([-+# ]\?\)\@='
  execute "syntax match TagbarFoldIcon '" . s:pattern . "'"
  highlight default link TagbarFoldIcon   Statement

  map <buffer> <silent> <Enter> :call ToggleFold()<CR>
  map <buffer> <silent> + :call IncreaseVariableLevel()<CR>
  map <buffer> <silent> - :call DecreaseVariableLevel()<CR>
  map <buffer> <silent> <Del> :call RemoveVariable()<CR>
endfunction

function! IncreaseVariableLevel()
  call ChangeLevel(1)
endfunction

function! DecreaseVariableLevel()
  call ChangeLevel(-1)
endfunction

function! RemoveVariable()
  let line = line(".")
  let group = s:brkpts_locals.expressions
  if group.line < line
    if !group.isFolded
      let pos = 0
      for variable in group.variables
        if variable.line == line
          call remove(s:brkpts_locals.expressions.variables, pos)
          call <SID>PrintLocals()
          execute 'normal ' . line . 'G'
          normal zz
          return
        endif
        let pos += 1
      endfor
    endif
  endif
endfunction

function! ChangeLevel(incr)
  let line = line(".")
  for key in keys(s:brkpts_locals)
    let group = s:brkpts_locals[key]
    if type(group) != type({}) || !has_key(group, "variables")
      unlet group
      continue
    endif
    if group.line < line
      if !group.isFolded
        for variable in group.variables
          if variable.line == line
            let variable.level += a:incr
            call <SID>PrintLocals()
            execute 'normal ' . line . 'G'
            normal zz
            return
          endif
        endfor
      endif
    endif
    unlet group
  endfor
endfunction

function! ToggleFold()
  let line = line(".")
  for key in keys(s:brkpts_locals)
    let group = s:brkpts_locals[key]
    if type(group) != type({}) || !has_key(group, "variables")
      unlet group
      continue
    endif
    if group.line == line
      if group.isFolded
        let group.isFolded = 0
      else
        let group.isFolded = 1
      endif
      call <SID>PrintLocals()
      execute 'normal ' . line . 'G'
      normal zz
      break
    endif
    unlet group
  endfor
endfunction

function! s:InitLocal(container)
  let a:container.isFolded = 1
  let a:container.variables = []
endfunction

function! s:PopulateLocals()
  call <SID>InitLocal(s:brkpts_locals.locals)
  call <SID>InitLocal(s:brkpts_locals.arguments)
  if !has_key(s:brkpts_locals.expressions, "variables")
    call <SID>InitLocal(s:brkpts_locals.expressions)
  endif
  "let s:brkpts_locals.loaded = 1

  let context = s:GetRemoteContext()
  let [mode, funcName, lineNo] = ParseContext(context)
  if funcName != ''
    let funcName = s:GetFuncRefName(funcName)
    let funcOutput = s:GetVimCmdOutput('function '.funcName)
    let splitFunc = split(funcOutput, '\n')
    for key in keys(s:brkpts_locals)
      let group = s:brkpts_locals[key]
      if type(group) != type({}) || !has_key(group, "variables")
        unlet group
        continue
      endif
      let variables = group.parse(splitFunc)
      for var in variables
        call add(group.variables, {"name": var, "level": 1})
      endfor
      unlet variables
      unlet group
    endfor
  endif
endfunction

function! s:GetFuncRefName(name)
  if (a:name+0 > 0)
    let funcName = '{' . a:name . '}'
  else
    let funcName = a:name
  endif
  return funcName
endfunction

let s:brkpts_locals.locals.isFolded = 0

function! s:GetLocalizedStrings()
  " add a targeted breakpoint, extract the localized token phrase for
  " 'line' into s:str_line, and delete that breakpoint afterwards
  exec "breakadd func 1 ADummyFunc"
  let breakList = genutils#GetVimCmdOutput('breaklist')
  let matchedLn = matchstr(breakList, '\v\_s*\zs\d+\s+func\s+ADummyFunc\s+.{-}1\ze.{-}\_s*')
  exec substitute(matchedLn, '\v(\d+)\s+func\s+ADummyFunc\s+(.{-})\s+1',
              \ 'breakdel \1 | let s:str_line = ''\2''', '')
  " extract the localized token phrase into s:str_in_line
  call s:_GenContext()
  exec substitute(g:BPCurContext, '\v^.*GenContext(.{-})\d+.*$', 'let s:str_in_line=''\1''', '')
endfunction

function! s:PrintBacktrace() 
  let bufBacktraceNr = bufwinnr(g:BreakPts_backtrace_title)  
  if bufBacktraceNr == -1
    exec "rightbelow new " . g:BreakPts_backtrace_title
    call breakpts#SetupBuf()
    let s:opMode = 'user'
  elseif bufwinnr("%") != bufBacktraceNr
    noautocmd exec bufBacktraceNr . 'wincmd w'
  endif
 
  silent %delete_

  let context = s:GetRemoteContext()
  let [mode, name, lineNo] = ParseContext(context)
  if name != ''
    let backtraceList = split(substitute(context, "^function ", "", ""),'\.\.')
    let backtraceList = map(backtraceList, 'split(v:val, ",.*".s:str_line." ")')
    let pos = 0
    if exists("b:traceInfo")
      if !empty(b:traceInfo)
        call remove(b:traceInfo,0,-1)
      endif
    else
      let b:traceInfo = []
    endif
    for trace in backtraceList
      if len(trace) > 1
        call add(b:traceInfo, {"function": trace[0], "line": trace[1]})
      else
        if has("patch-7.4.879")
          call substitute(trace[0], '\(.*\)\[\(\d\+\)\]', 
            \ '\=add(b:traceInfo, { "function": submatch(1), "line": submatch(2)})', '') 
        else
          call add(b:traceInfo, {"function": trace[0], "line": FindLineFunctionCall(traceInfo,trace[0], pos)})
        endif 
      endif
      let traceObj = b:traceInfo[pos]
      let line = traceObj.function
      let lineNum = traceObj.line
      if lineNum != -1
        let line = line . ":" . lineNum
      endif
      silent put ='[' . pos . '] ' . line
      let traceObj.offset = line(".")
      let pos += 1
    endfor
  endif

  let s:pattern = '\[\|\]'
  execute "syntax match TagbarFoldIcon '" . s:pattern . "'"
  highlight default link TagbarFoldIcon   Statement

  map <buffer> <silent> <Enter> :call GoToFunction()<CR>
endfunction

function! FindLineFunctionCall(traceInfo, functionName, pos)
  if pos == 0
    "first level backtrace, imposible to infere
    return -1
  else
    let trace = traceInfo[pos-1] 
    "TODO: List function and find ocurrences of functionName. If only one
    "match, thats the line, else add as proposals
    return -1
  endif
endfunction

function! GoToFunction()
  let offset = line(".")
  for trace in b:traceInfo
    if trace.offset == offset
      call s:OpenListing(0, g:breakpts#BM_FUNCTION, '', trace.function)
      let line = trace.line
      if line != -1
        call search('^'. line .'\>', 'w')
      endif
      break
    endif
  endfor
endfunction

" Initialization }}}


" Browser functions {{{

function! breakpts#BrowserMain(...) " {{{
  call s:GetLocalizedStrings()
  if s:myBufNum == -1
    exec g:brkptsLayout . " " . g:BreakPts_title
    let s:myBufNum = bufnr('%')
  else
    let buffer_win = bufwinnr(s:myBufNum)
    if buffer_win == -1
      exec 'sbuffer '. s:myBufNum
      let s:opMode = 'user'
    else
      exec buffer_win . 'wincmd w'
    endif
  endif

  let browserMode = ''
  let remoteServer = ''
  if a:0 > 0
    if a:1 =~ '^+f\%[unction]$'
      let browserMode = g:breakpts#BM_FUNCTIONS
    elseif a:1 =~ '^+s\%[cripts]$'
      let browserMode = g:breakpts#BM_SCRIPTS
    elseif a:1 =~ '^+b\%[reakpts]$'
      let browserMode = g:breakpts#BM_BRKPTS
    else
      let remoteServer = a:1
    endif
  endif

  if browserMode != ''
    call s:Browser(1, browserMode, '', '')
  else
    call breakpts#BrowserRefresh(0)
    if remoteServer != ''
      call <SID>SetRemoteServer(remoteServer)
    endif
  endif

endfunction " }}}

" Call this function to convert any buffer to a breakpts buffer.
function! breakpts#SetupBuf() " {{{
  call genutils#OptClearBuffer()
  call s:SetupBuf(0)
endfunction " }}}

" Refreshes with the same mode.
function! breakpts#BrowserRefresh(force) " {{{
  call s:Browser(a:force, s:GetBrowserMode(), s:GetListingId(),
        \ s:GetListingName())
endfunction " }}}

" The commands local to the browser window can directly call this, as the
"   browser window is gauranteed to be already open (which is where the user
"   must have executed the command in the first place).
function! s:Browser(force, browserMode, id, name) " {{{
  call s:ClearSigns()
  let bufBrowserNr = bufwinnr(g:BreakPts_title)  
  if bufBrowserNr == -1
    exec "vertical rightbelow new " . g:BreakPts_title
    call breakpts#SetupBuf()
    let s:opMode = 'user'
    call s:ClearSigns()
  elseif bufwinnr("%") != bufBrowserNr
    noautocmd exec bufBrowserNr . 'wincmd w'
  endif

  " First mark the current position so navigation will work.
  normal! mt
  setlocal modifiable
  if a:force || getline(1) == ''
    call genutils#OptClearBuffer()

  " Refreshing the current listing or list view.
  elseif ((a:browserMode == g:breakpts#BM_FUNCTION ||
        \  a:browserMode == g:breakpts#BM_SCRIPT) &&
        \ s:GetListingName() == a:name) ||
        \((a:browserMode == g:breakpts#BM_FUNCTIONS ||
        \  a:browserMode == g:breakpts#BM_SCRIPTS ||
        \  a:browserMode == g:breakpts#BM_BRKPTS) &&
        \ a:browserMode == s:GetBrowserMode())
    call genutils#SaveHardPosition('BreakPts')
    silent! undo
  endif

  if a:name != ''
    call s:List_{a:browserMode}(a:id, a:name)
  else
    let output = s:GetVimCmdOutput(s:cmd_{a:browserMode})
    let lastLine = line('$')
    if exists('*s:Process_{a:browserMode}_output')
      call s:Process_{a:browserMode}_output(output)
    else
      silent! $put =output
    endif
    silent! exec '1,' . (lastLine + 1) . 'delete _'
    call append(0, s:header{a:browserMode})
    if s:remoteServName != ""
      if s:remoteServName == "."
        call append(0, "[LOCAL DEBUG]")
      else
        call append(0, "[DEBUG ".s:remoteServName ."]")
      endif
    endif
  endif
  setlocal nomodifiable
  call s:MarkBreakPoints(a:name)
  if genutils#IsPositionSet('BreakPts')
    call genutils#RestoreHardPosition('BreakPts')
    call genutils#ResetHardPosition('BreakPts')
  endif
  call s:SetupBuf(a:name == "")
endfunction " }}}

function! s:Process_functions_output(output) " {{{
  " Extract the function name part from listing, and set them as lines after
  " sorting.
  call setline(line('$')+1, sort(map(split(a:output, "\n"),
        \ "matchstr(v:val, '".'function \zs\%(\k\|[<>]\|#\)\+'."')")))
endfunction " }}}

function! s:List_script(curScriptId, curScript) " {{{
  let lastLine = line('$')
  silent! call append('$', 'Script: ' . a:curScript . ' (Id: ' . a:curScriptId
        \ . ')')
  let v:errmsg = ''
  silent! exec '$read ' . a:curScript
  if v:errmsg != ''
    call confirm("There was an error loading the script, make sure the path " .
          \ "is absolute or is reachable from current directory: \'" . getcwd()
          \ . "\".\nNOTE: Filenames with regular expressions are not supported."
          \ ."\n".v:errmsg, "&OK", 1, "Error")
    return
  endif
  silent! exec '1,' . lastLine . 'delete _'
  " Insert line numbers in the front. Use only enough width required.
  call genutils#SilentSubstitute('^',
        \ '2,$s//\=strpart((line(".") - 1)."    ", 0, '.
        \ (strlen(string(line('$')))+1).')/')
  if s:remoteServName != ""
    if s:remoteServName == "."
      call append(0, "[LOCAL DEBUG]")
    else
      call append(0, "[DEBUG ".s:remoteServName ."]")
    endif
  endif
endfunction " }}}

function! s:List_function(sid, funcName) " {{{

  let funcName = s:GetFuncRefName(a:funcName)

  let funcListing = s:GetVimCmdOutput('function ' . funcName)
  if funcListing == ""
    return
  endif

  let lastLine = line('$')
  silent! $put =funcListing
  silent! exec '1,' . (lastLine + 1) . 'delete _'
  if g:brkptsModFuncHeader
    call genutils#SilentSubstitute('^\(\s\+\)function ', '1s//\1function! /')
  endif
  call s:FixInitWhite()
  if s:remoteServName != ""
    if s:remoteServName == "."
      call append(0, "[LOCAL DEBUG]")
    else
      call append(0, "[DEBUG ".s:remoteServName ."]")
    endif
  endif
endfunction " }}}

function! s:GetBrowserMode() " {{{
  let headLine = getline(2)
  if headLine =~ '^\s*function!\= '
    let mode = g:breakpts#BM_FUNCTION
  elseif headLine =~ '^'.s:header{g:breakpts#BM_FUNCTIONS}.'$'
    let mode = g:breakpts#BM_FUNCTIONS
  elseif headLine =~ '^Script: '
    let mode = g:breakpts#BM_SCRIPT
  elseif headLine =~ '^'.s:header{g:breakpts#BM_SCRIPTS}.'$'
    let mode = g:breakpts#BM_SCRIPTS
  elseif headLine =~ '^'.s:header{g:breakpts#BM_BRKPTS}.''
    let mode = g:breakpts#BM_BRKPTS
  else
    let mode = g:brkptsDefStartMode
  endif
  return mode
endfunction " }}}

" Browser functions }}}


" Breakpoint handling {{{

function! s:DoAction() " {{{
  if line('.') <= 2 " Ignore the header lines.
    return
  endif
  let browserMode = s:GetBrowserMode()
  if browserMode == g:breakpts#BM_BRKPTS
    if match(getline('.'), '\d') == -1 " no breakpoints defined
      return
    endif
    exec s:GetBrklistLineParser(getline('.'), 'name', 'mode')
    if mode ==# 'func'
      let mode = g:breakpts#BM_FUNCTION
    elseif mode ==# 'file'
      let mode = g:breakpts#BM_SCRIPT
    endif
    call s:OpenListing(0, mode, 0, name)
    call search('^'.lnum.'\>', 'w')
  elseif browserMode == g:breakpts#BM_SCRIPTS
    let curScript = s:GetScript()
    let curScriptId = s:GetScriptId()
    if curScript != '' && curScriptId != ''
      call s:OpenListing(0, g:breakpts#BM_SCRIPT, curScriptId, curScript)
    endif
  elseif browserMode == g:breakpts#BM_FUNCTION
    let curFunc = s:EvaluateSelection(1)
    if curFunc != ''
      let scrPrefix = matchstr(curFunc, '^\%(s:\|<SID>\)')
      if scrPrefix != ''
        let curSID = s:GetListingId()
        let curFunc = strpart(curFunc, strlen(scrPrefix))
        if curSID == ""
          let curSID = s:SearchForSID(curFunc)
        endif
        if curSID == ""
          echohl ERROR | echo "Sorry, SID couldn't be determined!!!" |
                \ echohl NONE
          return
        endif
        let curFunc = '<SNR>' . curSID . '_' . curFunc
      endif
      call s:OpenListing(0, g:breakpts#BM_FUNCTION, '', curFunc)
    endif
  elseif browserMode == g:breakpts#BM_FUNCTIONS
        \ || browserMode == g:breakpts#BM_SCRIPT
    let curFunc = s:GetFuncName()
    if curFunc != ''
      let scrPrefix = matchstr(curFunc, '^\%(s:\|<SID>\)')
      if scrPrefix != ''
        let curSID = s:GetListingId()
        let curFunc = strpart(curFunc, strlen(scrPrefix))
        if curSID == ""
          let curSID = s:SearchForSID(curFunc)
        endif
        if curSID == ""
          echohl ERROR | echo "Sorry, SID couldn't be determined!!!" |
                \ echohl NONE
          return
        endif
        let curFunc = '<SNR>' . curSID . '_' . curFunc
      endif
      call s:OpenListing(0, g:breakpts#BM_FUNCTION, '', curFunc)
    endif
  endif
endfunction " }}}

function! s:OpenListing(force, mode, id, name) " {{{
  call s:OpenListingWindow(0)
  call s:Browser(a:force, a:mode, a:id, a:name)
endfunction " }}}

" Accepts a partial path valid under 'rtp'
function! s:OpenScript(rtPath) " {{{
  let path = a:rtPath
  if ! filereadable(path) && fnamemodify(path, ':p') != path
    for dir in split(&rtp, genutils#CrUnProtectedCharsPattern(','))
      if filereadable(dir.'/'.a:rtPath)
        let path = dir.'/'.a:rtPath
      endif
    endfor
  else
    let path = fnamemodify(path, ':p')
  endif
  call s:OpenListing(0, g:breakpts#BM_SCRIPT, 0, path )
endfunction " }}}

" Pattern to extract the breakpt number out of the :breaklist.
let s:BRKPT_NR = '\%(^\|['."\n".']\+\)\s*\zs\d\+\ze\s\+\%(func\|file\)' .
      \ '\s\+\S\+\s\+line\s\+\d\+'
" Mark breakpoints {{{
function! s:MarkBreakPoints(name)
  let b:brkPtLines = []
  let brkPts = s:GetVimCmdOutput('breaklist')
  let pat = ''
  let browserMode = s:GetBrowserMode()
  if browserMode == g:breakpts#BM_FUNCTIONS
    let pat = '\d\+\s\+func \zs\%(<SNR>\d\+_\)\?\k\+\ze\s\+'.s:str_line.' \d\+'
  elseif browserMode == g:breakpts#BM_FUNCTION
    let pat = '\d\+\s\+func ' . a:name . '\s\+'.s:str_line.' \zs\d\+'
  elseif browserMode == g:breakpts#BM_SCRIPTS
    let pat = '\d\+\s\+file \zs\f\+\ze\s\+'.s:str_line.' \d\+'
  elseif browserMode == g:breakpts#BM_SCRIPT
    let pat = '\d\+\s\+file \m' . escape(a:name, "\\") . '\M\s\+'.s:str_line.' \zs\d\+'
  elseif browserMode == g:breakpts#BM_BRKPTS
    let pat = s:BRKPT_NR
  endif
  let loc = ''
  let curIdx = 0
  if pat != ''
    while curIdx != -1 && curIdx < strlen(brkPts)
      let loc = matchstr(brkPts, pat, curIdx)
      if loc != ''
        let line = 0
        if (browserMode == g:breakpts#BM_FUNCTION ||
              \ browserMode == g:breakpts#BM_FUNCTIONS) &&
              \ search('^'. loc . '\>')
          let line = line('.')
        elseif browserMode == g:breakpts#BM_SCRIPTS &&
              \ search('\V'.escape(loc, "\\"))
          let line = line('.')
        elseif browserMode == g:breakpts#BM_SCRIPT
          let line = loc + 1
        elseif browserMode == g:breakpts#BM_BRKPTS && search('^\s*'.loc)
          let line = line('.')
        endif
        if line != 0
          if index(b:brkPtLines, line) == -1 && has("signs")
            exec 'sign place ' . line . ' line=' . line .
                  \ ' name=VimBreakPt buffer=' . bufnr('%')
          endif
          call add(b:brkPtLines, line)
        endif
      endif
      let curIdx = matchend(brkPts, pat, curIdx)
    endwhile
  endif
  if len(b:brkPtLines) != 0
    call sort(b:brkPtLines, 'genutils#CmpByNumber')
    if g:brkptsCreateFolds && exists(':FoldNonMatching')
      silent! exec "FoldShowLines " . join(b:brkPtLines, ',') . " " .
            \ g:brkptsFoldContext
      1
    endif
  else
    exec 'sign place 9999 line=1'
          \ ' name=EmptyBreakPt buffer=' . bufnr('%')
  endif
  call s:MarkCurLineInCntxt(s:curLineInCntxt+2)
  return
endfunction

function! s:MarkCurLineInCntxt(pos)
  silent! syn clear BreakPtsContext
  if s:curLineInCntxt != '' && s:GetListingName() == s:curNameInCntxt
    let useSigns = 0
    if useSigns
      "when highlight is too much set a sign (and clear previous)
      exe ':sign place ' . a:pos . ' name=' . s:VimBreakDbgCur . ' line=' . a:pos . ' buffer=' . winbufnr(0)
      try
        exe ':sign unplace ' . old_cur_pos . ' buffer=' . winbufnr(0)
      catch /.*/
      endtry
    else
      exec 'match BreakPtsContext "\%'.a:pos.'l.*"'
    endif

  endif
endfunction
" }}}

function! s:NextBrkPt(dir) " {{{
  let nextBP = genutils#BinSearchList(b:brkPtLines, 0, len(b:brkPtLines)-1,
        \ line('.'), function('genutils#CmpByNumber'))
  if nextBP >= 0 && nextBP <= len(b:brkPtLines)
    exec b:brkPtLines[nextBP]
  endif
endfunction " }}}

" Add/Remove breakpoints {{{
" Add breakpoint at the current line.
function! s:AddBreakPoint(name, mode, browserMode, brkLine)
  let v:errmsg = ""
  let lnum = a:brkLine
  let browserMode = a:browserMode
  let mode = a:mode
  if browserMode == g:breakpts#BM_FUNCTION
    let name = a:name
  elseif browserMode == g:breakpts#BM_SCRIPT
    let name = substitute(a:name, "\\\\", '/', 'g')
  elseif browserMode == g:breakpts#BM_BRKPTS
    exec s:GetBrklistLineParser(getline('.'), 'name', 'mode')
  endif
  if lnum == 0
    call s:ExecCmd('breakadd ' . mode . ' ' . name)
  else
    call s:ExecCmd('breakadd ' . mode . ' ' . lnum . ' ' . name)
  endif
  if v:errmsg != ""
    echohl ERROR | echo s:GetMessage("Error setting breakpoint for: ",
          \ name, lnum)."\n".v:errmsg | echohl None
    return
  endif
  echo s:GetMessage("Break point set for: ", name, lnum)
  if browserMode == g:breakpts#BM_BRKPTS
    " We need to update the current line for the new id.
    " Get the breaklist output, the last line would be for the latest
    "   breakadd.
    setl modifiable
    let brkLine = matchstr(s:GetVimCmdOutput('breaklist'), s:BRKPT_NR.'$')
    call setline('.',
          \ substitute(getline('.'), '^\(\s*\)\d\+', '\1'.brkLine, ''))
    setl nomodifiable
  endif
  if index(b:brkPtLines, line('.')) == -1 && has("signs")
    exec 'sign place ' . line('.') . ' line=' . line('.') .
          \ ' name=VimBreakPt buffer=' . winbufnr(0)
  endif
  call add(b:brkPtLines, line('.'))
endfunction

function! s:GetMessage(msg, name, brkLine)
  return a:msg . a:name . "(line: " . a:brkLine . ")."
endfunction

" Remove breakpoint at the current line.
function! s:RemoveBreakPoint(name, mode, browserMode, brkLine)
  let v:errmsg = ""
  let lnum = a:brkLine
  let browserMode = a:browserMode
  let mode = a:mode
  if browserMode == g:breakpts#BM_FUNCTION
    let name = a:name
    let mode = 'func'
  elseif browserMode == g:breakpts#BM_SCRIPT
    let name = a:name
    let mode = 'file'
  elseif browserMode == g:breakpts#BM_BRKPTS
    exec s:GetBrklistLineParser(getline('.'), 'name', 'mode')
  endif
  if lnum == 0
    call s:ExecCmd('breakdel ' . mode . ' ' . name)
  else
    call s:ExecCmd('breakdel ' . mode . ' ' . lnum . ' ' . name)
  endif
  if v:errmsg != ""
    echohl ERROR | echo s:GetMessage("Error clearing breakpoint for: ",
          \ name, lnum) . "\nRefresh to see the latest breakpoints."
          \ | echohl None
    return
  endif
  echo s:GetMessage("Break point cleared for: ", name, lnum)
  if index(b:brkPtLines, line('.')) != -1
    call remove(b:brkPtLines, index(b:brkPtLines, line('.')))
    if index(b:brkPtLines, line('.')) == -1 && has("signs")
      sign unplace
    endif
  endif
endfunction

function! s:ToggleBreakPoint()
  let brkLine = -1
  let browserMode = s:GetBrowserMode()
  if browserMode == g:breakpts#BM_FUNCTIONS ||
        \ browserMode == g:breakpts#BM_SCRIPTS
    return
  endif
  if browserMode == g:breakpts#BM_FUNCTION
    let name = s:GetListingName()
    let mode = 'func'
    if line('.') > 2 && line('.') < line('$')
      let brkLine = matchstr(getline('.'), '^\d\+')
      if brkLine == ''
        let brkLine = 0
      endif
    endif
  elseif browserMode == g:breakpts#BM_SCRIPT
    let name = s:GetListingName()
    let mode = 'file'
    if line('.') == 1
      +
    endif
    let brkLine = line('.')
    let brkLine = brkLine - 1
  elseif browserMode == g:breakpts#BM_BRKPTS
    exec s:GetBrklistLineParser(getline('.'), 'name', 'mode')
    let brkLine = line('.')
  endif
  if brkLine >= 0
    if index(b:brkPtLines, line('.')) != -1
      call s:RemoveBreakPoint(name, mode, browserMode, brkLine)
    else
      call s:AddBreakPoint(name, mode, browserMode, brkLine)
    endif
  endif
endfunction

function! s:ClearSigns()
  if exists('b:brkPtLines') && len(b:brkPtLines) > 0
    call genutils#SaveHardPosition('ClearSigns')
    let linesCleared = []
    for nextBrkLine in b:brkPtLines
      if index(linesCleared, nextBrkLine) == -1 && has("signs")
        exec nextBrkLine
        exec 'sign unplace' nextBrkLine
      endif
      call add(linesCleared, nextBrkLine)
    endfor
    call genutils#RestoreHardPosition('ClearSigns')
    call genutils#ResetHardPosition('ClearSigns')
  endif
endfunction

function! breakpts#SaveBrkPts(varName)
  let brkList = s:GetVimCmdOutput('breaklist')
  if brkList =~ '.*No breakpoints defined.*'
    call confirm("There are currently no breakpoints defined.",
          \ "&OK", 1, "Info")
  else
    let brkLines = split(brkList, "\n")
    call map(brkLines,
          \ "substitute(v:val, '".'\s*\d\+\s\+\(\S\+\)\s\+\(\S\+\)\s\+line\s\+\(\d\+\)'.
          \ "', ':breakadd \\1 \\3 \\2', '')")
    call map(brkLines, "substitute(v:val, '\\\\', '/', 'g')")
    let varName = (a:varName =~ '^@\a$'?'':(a:varName =~ '^g:'?'':'g:')).a:varName
    exec 'let '.varName.' = join(brkLines, "\n")'
    call confirm("The breakpoints have been saved into global variable: " .
          \ a:varName, "&OK", 1, "Info")
  endif
endfunction

function! breakpts#ClearBPCounters()
    let s:bpCounters = {}
endfunction

function! breakpts#ClearAllBrkPts()
  let choice = confirm("Do you want to clear all the breakpoints?",
        \ "&Yes\n&No", "1", "Question")
  if choice == 1
    call breakpts#ClearBPCounters()
    let breakList = s:GetVimCmdOutput('breaklist')
    if match(breakList, '\d') == -1 " breakpoints not defined
      let clearCmds = substitute(breakList,
            \ '\(\d\+\)\%(\s\+\%(func\|file\)\)\@=' . "[^\n]*",
            \ ':breakdel \1', 'g')
      let v:errmsg = ''
      call s:ExecCmd(clearCmds)
      if v:errmsg != ''
        call confirm("There were errors clearing breakpoints.\n".v:errmsg,
              \ "&OK", 1, "Error")
      endif
    endif
  endif
endfunction

function! s:GetBrklistLineParser(line, nameVar, modeVar)
  return substitute(a:line,
        \ '^\s*\d\+\s\+\(\S\+\)\s\+\(.\{-}\)\s\+'.s:str_line.'\s\+\(\d\+\)$', "let ".
        \ a:modeVar."='\\1' | let ".a:nameVar."='\\2' | let lnum=\\3", '')
endfunction
" Add/Remove breakpoints }}}

" Breakpoint handling }}}


" Utilities {{{

" {{{
" Get the function/script name that is currently being listed.
" As it appears in the :breaklist command.
function! s:GetListingName()
  let browserMode = s:GetBrowserMode()
  if browserMode == g:breakpts#BM_FUNCTION
    return s:GetListedFunction()
  elseif browserMode == g:breakpts#BM_SCRIPT
    return s:GetListedScript()
  else
    return ''
  endif
endfunction

" Get the function/script id that is currently being listed.
" As it appears in the :breaklist command.
function! s:GetListingId()
  let browserMode = s:GetBrowserMode()
  if browserMode == g:breakpts#BM_FUNCTION
    return s:ExtractSID(s:GetListedFunction())
  elseif browserMode == g:breakpts#BM_SCRIPT
    return s:GetListedScriptId()
  else
    return ''
  endif
endfunction

function! s:GetListedScript()
  return matchstr(getline(2), '^Script: \zs\f\+\ze (Id: \d\+)')
endfunction

function! s:GetListedScriptId()
  return matchstr(getline(2), '^Script: \f\+ (Id: \zs\d\+\ze)')
endfunction

function! s:GetScript()
  return matchstr(getline('.'), '^\s*\d\+: \zs\f\+\ze$')
endfunction

function! s:GetScriptId()
  return matchstr(getline('.'), '^\s*\zs\d\+\ze: \f\+$')
endfunction

function! s:GetFuncName()
  let funcName = getline('.')
  if match(funcName, "[~`!@$%^&*()-+={}[\\]|\\;'\",.?/]") != -1
    let funcName = ''
  endif
  return funcName
endfunction

function! s:GetListedFunction() " Includes SID.
  return matchstr(getline(2),
        \ '\%(^\s*function!\? \)\@<=\%(<SNR>\d\+_\)\?\f\+\%(([^)]*)\)\@=')
endfunction

function! s:ExtractSID(funcName)
  if a:funcName =~ '^\k\+#' " An autoloaded function
    " Search for a possible SID for this prefix.
    let auloadPrefix = matchstr(a:funcName, '^\k\+\ze#')
    let sid = ''
    if has_key(s:auloadedSids, auloadPrefix)
      let sid = s:auloadedSids[auloadPrefix]
    else
      let loadedScripts = split(s:GetVimCmdOutput('scriptnames'), "\n")
      for script in loadedScripts
        if script =~ 'autoload[/\\]'.auloadPrefix.'.vim$'
          let sid = matchstr(script, '\d\+')
          let s:auloadedSids[auloadPrefix] = sid
        endif
      endfor
    endif
    return sid
  else
    return matchstr(a:funcName, '^<SNR>\zs\d\+\ze_')
  endif
endfunction

function! s:ExtractFuncName(funcName)
  let sidEnd = matchend(a:funcName, '>\d\+_')
  let sidEnd = (sidEnd == -1) ? 0 : sidEnd
  let funcEnd = stridx(a:funcName, '(') - sidEnd
  let funcEnd = (funcEnd < 0) ? strlen(a:funcName) : funcEnd
  return strpart(a:funcName, sidEnd, funcEnd)
endfunction
" }}}

function! s:SearchForSID(funcName) " {{{
  " First find the current maximum SID (keeps increasing as more scrpits get
  "   loaded, ftplugin, syntax and others).
  let maxSID = 0
  let scripts = s:GetVimCmdOutput('scriptnames')
  let maxSID = matchstr(scripts, "\\d\\+\\ze: [^\x0a]*$") + 0

  let i = 0
  while i <= maxSID
    if exists('*<SNR>' . i . '_' . a:funcName)
      return i
    endif
    let i = i + 1
  endwhile
  return ''
endfunction " }}}

function! s:OpenListingWindow(always) " {{{
  if s:opMode ==# 'WinManager' || a:always
    if s:funcBufNum == -1
      " Temporarily modify isfname to avoid treating the name as a pattern.
      let _isf = &isfname
      try
        set isfname-=\
        set isfname-=[
        if s:opMode ==# 'WinManager'
          if exists('+shellslash')
            call WinManagerFileEdit("\\\\".escape(s:BreakListing_title, ' '), 1)
          else
            call WinManagerFileEdit("\\".escape(s:BreakListing_title, ' '), 1)
          endif
        else
          if exists('+shellslash')
            exec "sp \\\\". escape(s:BreakListing_title, ' ')
          else
            exec "sp \\". escape(s:BreakListing_title, ' ')
          endif
        endif
      finally
        let &isfname = _isf
      endtry
      let s:funcBufNum = bufnr('%') + 0
    else
      if s:opMode ==# 'WinManager'
        call WinManagerFileEdit(s:funcBufNum, 1)
      else
        let win = bufwinnr(s:funcBufNum)
        if win != -1
          exec win.'wincmd w'
        else
          exec 'sp #'.s:funcBufNum
        endif
      endif
    endif
    call s:SetupBuf(0)
  endif
endfunction " }}}

function! s:ReloadCurrentScript() " {{{
  let browserMode = s:GetBrowserMode()
  let curScript = ''
  if browserMode == g:breakpts#BM_SCRIPTS
    let curScript = s:GetScript()
    let needsRefresh = 0
  elseif browserMode == g:breakpts#BM_SCRIPT
    let curScript = s:GetListedScript()
    let needsRefresh = 1
  endif
  if curScript != ''
    if curScript =~ '/plugin/[^/]\+.vim$' " If a plugin.
      let plugName = substitute(fnamemodify(curScript, ':t:r'), '\W', '_', 'g')
      let varName = s:GetPlugVarIfExists(curScript)
      if varName == ''
        let choice = confirm("Couldn't identify the global variable that ".
              \ "indicates that this plugin has already been loaded.\nDo you " .
              \ "want to continue anyway?", "&Yes\n&No", 1, "Question")
        if choice == 2
          return
        endif
      else
        call s:ExecCmd('unlet ' . varName)
      endif
    endif

    let v:errmsg = ''
    call s:ExecCmd('source ' . curScript)
    " FIXME: Are we able to see the remote errors here?
    if v:errmsg == ''
      call confirm("The script: \"" . curScript .
            \ "\" has been successfully reloaded.", "&OK", 1, "Info")
      if needsRefresh
        call breakpts#BrowserRefresh(0)
      endif
    else
      call confirm("There were errors reloading script: \"" . curScript .
            \ "\".\n" . v:errmsg, "&OK", 1, "Error")
    endif
  endif
endfunction " }}}

function! s:GetPlugVarIfExists(curScript) " {{{
  let plugName = fnamemodify(a:curScript, ':t:r')
  let varName = 'g:loaded_' . plugName
  if ! s:EvalExpr("exists('".varName."')")
    let varName = 'g:loaded_' . substitute(plugName, '\W', '_', 'g')
    if ! s:EvalExpr("exists('".varName."')")
      let varName = 'g:loaded_' . substitute(plugName, '\u', '\L&', 'g')
      if ! s:EvalExpr("exists('".varName."')")
        return ''
      endif
    endif
  endif
  return varName
endfunction " }}}

" functions SetupBuf/Quit {{{
function! s:SetupBuf(full)
  call genutils#SetupScratchBuffer()
  setlocal nowrap
  setlocal bufhidden=hide
  setlocal iskeyword+=< iskeyword+=> iskeyword+=: iskeyword+=_ iskeyword+=#
  set ft=vim
  " Don't make the <SNR> part look like an error.
  if hlID("vimFunctionError") != 0
    syn clear vimFunctionError
    syn clear vimCommentString
  endif
  syn match vimFunction "\<fu\%[nction]!\=\s\+\U.\{-}("me=e-1 contains=@vimFuncList nextgroup=vimFuncBody
  syn match vimFunction "^\k\+$"
  syn region vimCommentString contained oneline start='\%(^\d\+\s*\)\@<!\S\s\+"'ms=s+1 end='"'
  syn match vimLineComment +^\d\+\s*[ \t:]*".*$+ contains=@vimCommentGroup,vimCommentString,vimCommentTitle
  syn match BreakPtsHeader "^\%1l\%(Script:\|Scripts:\|Functions:\|Breakpoints:\).*"
  syn match BreakPtsScriptLine "^\s*\d\+: \f\+$" contains=BreakPtsScriptId
  syn match BreakPtsScriptId "^\s*\d\+" contained

  if a:full
    " Invert these to mean close instead of open.
    command! -buffer -nargs=? BreakPts :call <SID>BreakPtsLocal(<f-args>)
    nnoremap <buffer> <silent> <Plug>BreakPts :BreakPts<CR>
    nnoremap <silent> <buffer> q :BreakPts<CR>
  endif

  exec 'command! -buffer BPScripts :call <SID>Browser(0,
        \ "' . g:breakpts#BM_SCRIPTS . '", "", "")'
  exec 'command! -buffer BPFunctions :call <SID>Browser(0,
        \ "' . g:breakpts#BM_FUNCTIONS . '", "", "")'
  exec 'command! -buffer BPPoints :call <SID>Browser(0,
        \ "' . g:breakpts#BM_BRKPTS . '", "", "")'
  command! -buffer -nargs=? -complete=custom,ServerListComplete BPRemoteServ :call <SID>SetRemoteServer(<f-args>)
  command! -buffer BPBack :call <SID>NavigateBack()
  command! -buffer BPForward :call <SID>NavigateForward()
  command! -buffer -range BPSelect :call <SID>DoAction()
  command! -buffer BPOpen :call <SID>Open()
  command! -buffer BPToggle :call <SID>ToggleBreakPoint()
  command! -buffer BPRefresh :call breakpts#BrowserRefresh(0)
  command! -buffer BPNext :call <SID>NextBrkPt(1)
  command! -buffer BPPrevious :call <SID>NextBrkPt(-1)
  command! -buffer BPReload :call <SID>ReloadCurrentScript()
  command! -buffer BPClearCounters :BreakPtsClearBPCounters
  command! -buffer BPClearAll :BreakPtsClearAll
  command! -buffer -nargs=1 BPSave :BreakPtsSave <args>
  exec "command! -buffer -nargs=1 -complete=function BPListFunc " .
        \ ":call <SID>OpenListing(0, '".g:breakpts#BM_FUNCTION."', '', " .
        \ "substitute(<f-args>, '()\\=', '', ''))"
  exec "command! -buffer -nargs=1 -complete=file BPListScript " .
        \ ":call <SID>OpenScript(<f-args>)"
  nnoremap <silent> <buffer> <BS> :BPBack<CR>
  nnoremap <silent> <buffer> <Tab> :BPForward<CR>
  nnoremap <silent> <buffer> <CR> :BPSelect<CR>
  xnoremap <silent> <buffer> <CR> :BPSelect<CR>
  nnoremap <silent> <buffer> o :BPOpen<CR>
  nnoremap <silent> <buffer> <2-LeftMouse> :BPSelect<CR>
  nnoremap <silent> <buffer> <F9> :BPToggle<CR>
  nnoremap <silent> <buffer> R :BPRefresh<CR>
  nnoremap <silent> <buffer> [b :BPPrevious<CR>
  nnoremap <silent> <buffer> ]b :BPNext<CR>
  nnoremap <silent> <buffer> O :BPReload<CR>

  command! -buffer BPDBackTrace :call <SID>PrintBacktrace()
  command! -buffer BPDLocals :call <SID>PrintLocals()
  command! -buffer BPDWhere :call <SID>ShowRemoteContext()
  command! -buffer BPDCont :call <SID>Cont()
  command! -buffer BPDQuit :call <SID>ExecDebugCmd('quit')
  command! -buffer BPDNext :call <SID>Next()
  command! -buffer BPDStep :call <SID>Step()
  command! -buffer BPDFinish :call <SID>ExecDebugCmd('finish')
  command! -buffer -count=1 -nargs=1 BPDEvaluate :call <SID>EvaluateExpr(<f-args>, <count>)
  command! -buffer -count=1 -nargs=1 BPDPreEvaluate :call <SID>PreEvaluateExpr(<f-args>)
  command! -buffer -count=1 -nargs=1 BPDSetAutoCommand :call <SID>SetAutoCmd(<f-args>, <count>)
  command! -buffer -nargs=0 BPDClearAutoCommand :call <SID>ClearAutoCmd()

  call s:DefMap("n", "ContKey", "<F5>", ":BPDCont<CR>", 1)
  call s:DefMap("n", "QuitKey", "<S-F5>", ":BPDQuit<CR>", 1)
  call s:DefMap("n", "WhereKey", "<F7>", ":BPDWhere<CR>", 1)
  call s:DefMap("n", "NextKey", "<F12>", ":BPDNext<CR>", 1)
  call s:DefMap("n", "StepKey", "<F11>", ":BPDStep<CR>", 1)
  call s:DefMap("n", "FinishKey", "<S-F11>", ":BPDFinish<CR>", 1)
  call s:DefMap("n", "ClearAllKey", "<C-S-F9>", ":BPClearAll<CR>", 1)
  "call s:DefMap("n", "RunToCursorKey", "<C-F10>", ":BPDRunToCursor<CR>", 1)

  call s:DefMap("n", "EvalExprKey"   , "<F8>"  , ":<C-U>call <SID>EvaluateExpr(\"<C-R>=<SID>EvaluateSelection(0)<CR>\", v:count1)<CR>", 1)
  call s:DefMap("v", "EvalExprKey"   , "<F8>"  , ":<C-U>call <SID>EvaluateExpr(\"<C-R>=<SID>EvaluateSelection(1)<CR>\", v:count1)<CR>", 1)

  call s:DefMap("n", "PreEvalExprKey", "<S-F8>", ":<C-U>BPDPreEvaluate <C-R>=<SID>EvaluateSelection(0)<CR>", 0)
  call s:DefMap("v", "PreEvalExprKey", "<S-F8>", ":<C-U>BPDPreEvaluate <C-R>=<SID>EvaluateSelection(1)<CR>", 0)

  " A bit of a setup for syntax colors.
  highlight default link BreakPtsBreakLine WarningMsg
  highlight default BreakPtsContext ctermfg=17 ctermbg=45 guifg=#00005f guibg=#00dfff
  highlight default link BreakPtsHeader Comment
  highlight default link BreakPtsScriptId Number

  normal zM
endfunction

function! s:Cont()
  call <SID>ExecDebugCmd('cont')
  call <SID>AutoCmd()
endfunction

function! s:Next()
  call <SID>ExecDebugCmd('next')
  call <SID>AutoCmd()
endfunction

function! s:Step()
  call <SID>ExecDebugCmd('step')
  call <SID>AutoCmd()
endfunction

function! s:AutoCmd()
  if s:autoCmd != ""
    call <SID>EvaluateExpr(s:autoCmd, s:autoCmdLevel)
  endif
endfunction

function s:EvaluateSelection(visualmode)
  let l:selection = ""
  if a:visualmode
    let l:selection = s:VisualSelection()
  endif
  if empty(l:selection)
    let l:selection = expand("<cword>")
  endif
  " remove jumps for multiline commands
  return substitute(l:selection,'\\\?\n\(\d\+\)*', '', 'g')
endfunction

function! s:VisualSelection()
  try
    let a_save = @a
    normal! gv"ay
    return @a
  finally
    let @a = a_save
  endtry
endfunction

" With no arguments, behaves like quit, and with arguments, just refreshes.
function! s:BreakPtsLocal(...)
  if a:0 == 0
    call s:Quit()
  else
    call breakpts#BrowserMain(a:1)
  endif
endfunction

function! s:Quit()
  " The second condition is for non-buffer plugin buffers.
  if s:opMode !=# 'WinManager' || bufnr('%') != s:myBufNum
    if genutils#NumberOfWindows() == 1
      redraw | echohl WarningMsg | echo "Can't quit the last window" |
            \ echohl NONE
    else
      quit
    endif
  endif
endfunction " }}}

function! s:DefMap(mapType, mapKeyName, defaultKey, cmdStr, silent) " {{{
  let key = maparg('<Plug>BreakPts' . a:mapKeyName . a:mapType)
  " If user hasn't specified a key, use the default key passed in.
  if key == ""
    let key = a:defaultKey
  endif
  let specialarg = " <buffer> "
  if a:silent !=0
    let specialarg .= "<silent> "
  endif
  exec a:mapType . "noremap" . specialarg . key a:cmdStr
endfunction " DefMap " }}}

" Sometimes there is huge amount white-space in the front for some reason.
function! s:FixInitWhite() " {{{
  let nWhites = strlen(matchstr(getline(2), '^\s\+'))
  if nWhites > 0
    let _search = @/
    try
      let @/ = '^\s\{'.nWhites.'}'
      silent! %s///
      1
    finally
      let @/ = _search
    endtry
  endif
endfunction " }}}

function! s:SetRemoteServer(...) " {{{
  if a:0 == 0
    echo "Current remote Vim server: " . s:remoteServName
  else
    let servName = a:1
    if s:remoteServName != servName
      if servName == v:servername
        let servName = '.'
      endif
      let s:remoteServName = servName
      setl modifiable
      call genutils#OptClearBuffer()
      call breakpts#BrowserRefresh(1)
      setl nomodifiable
    endif
  endif
endfunction " }}}

function! s:EvalExpr(expr) " {{{
  if s:remoteServName !=# '.'
    try
      return remote_expr(s:remoteServName, a:expr)
    catch
      let v:errmsg = substitute(v:exception, '^[^:]\+:', '', '')
      call s:ShowRemoteError(v:exception, s:remoteServName)
      return ''
    endtry
  else
    let result = ''
    try
      exec 'let result =' a:expr
    catch
      " Ignore
    endtry
    return result
  endif
endfunction " }}}

function! s:GetVimCmdOutput(cmd) " {{{
  return s:EvalExpr('genutils#GetVimCmdOutput('.genutils#QuoteStr(a:cmd).')')
endfunction " }}}

function! s:ShowRemoteError(msg, servName) " {{{
  call confirm('Error executing remote command: ' . a:msg .
        \ "\nCheck that the Vim server with the name: " . a:servName .
        \ ' exists and that it has breakpts.vim installed.', '&OK', 1, 'Error')
endfunction " }}}

function! s:ExecCmd(cmd) " {{{
  if s:remoteServName !=# '.'
    try
      call remote_expr(s:remoteServName, "genutils#GetVimCmdOutput('".a:cmd."')")
    catch
      let v:errmsg = substitute(v:exception, '^[^:]\+:', '', '')
      call s:ShowRemoteError(v:exception, s:remoteServName)
      return 1
    endtry
  else
    silent! exec a:cmd
  endif
  return 0
endfunction " }}}

function! s:PreEvaluateExpr(expr) " {{{
  call <SID>EvaluateExpr(a:expr, v:count1)
endfunction

function! s:EvaluateExpr(expr, max) " {{{
  if s:remoteServName !=# '.' &&
        \ remote_expr(s:remoteServName, 'mode()') ==# 'c'
    redraw
    try 
      echo <SID>GetRemoteExpr(a:expr, a:max, 0)
      if !has_key(s:brkpts_locals.expressions, "variables")
        call s:InitLocal(s:brkpts_locals.expressions)
      endif
      if len(filter(copy(s:brkpts_locals.expressions.variables), "v:val.name == \"" . a:expr . "\"")) == 0
        call add(s:brkpts_locals.expressions.variables, {"name": a:expr, "level": 1})
        let bufLocalNr = bufwinnr(g:BreakPts_locals_title)  
        if bufLocalNr != -1
          call s:PrintLocals()
        endif
      endif
    catch
      echo "(ERROR): evaluating " . a:expr . " " . v:exception . ", " . v:throwpoint
    endtry
  endif
endfunction " }}}

function! s:GetRemoteExpr(expr, max, indent) " {{{
  return remote_expr(s:remoteServName, "breakpts#ToJson(" . a:expr . ", 0, " . a:max . ", " . a:indent . ")")
endfunction " }}}

" Inspect variables
"
" input: variable
" level: actual level of nest
" max: maximum level of nest
function! breakpts#ToJson(input, level, max, indent) " {{{
  let json = ''
  try 
    let compute = a:level < a:max
    let type = type(a:input)
    if type == type({})
      if compute
        let parts = copy(a:input)
        call map(parts, '"\"" . escape(v:key, "\"") . "\":" . breakpts#ToJson(v:val, ' . (a:level+1) . ',' . a:max . ", " . a:indent . ")")
        let space = repeat(" ", a:indent + a:level)
        let json .= "{\n" . space . join(values(parts), ",\n " . space) . "\n" . space ."}"
      else
        let json .= "{...}"
      endif
    elseif type == type([])
      if compute
        let parts = map(copy(a:input), 'breakpts#ToJson(v:val, ' . (a:level+1) . ', ' . a:max . ', ' . a:indent . ')')
        let space = repeat(" ", a:indent + a:level)
        let json .= "[" . join(parts, ",\n" . space) . "]\n"
      else
        let json .= "[...]"
      endif
    elseif type == type(function("tr"))
      if compute
        let dictFunc = substitute(string(a:input), "function('\\(.\\+\\)')", "\\1", "")
        if dictFunc+0 > 0
          let funcName = '{' . dictFunc . '}'
        else
          let funcName = a:input
        endif
        let json .= '"' . escape(genutils#ExtractFuncListing(funcName, 0, 0), '"') . "\""
      else
        let json .= "func(...)"
      endif
    elseif type == type("string")
      let json .= '"' . escape(a:input, '"') . "\""
    elseif type == type(1)
      let json .= '"' . a:input . "\""
    elseif type == type(0.1)
      let json .= '"' . string(a:input) . "\""
    else
      throw "Unknown type: " . type
    endif
  catch
    let json .= "(ERROR): " . v:exception . " in " . v:throwpoint
  endtry
  return json
endfunction " }}}

function! s:SetAutoCmd(expr, count) " {{{
    let s:autoCmd = a:expr
    let s:autoCmdLevel = a:count
endfunction " }}}

function! s:ClearAutoCmd() " {{{
    let s:autoCmd = ""
    let s:autoCmdLevel = 1
endfunction " }}}

function! s:ExecDebugCmd(cmd) " {{{
  try
    if s:remoteServName !=# '.' &&
          \ remote_expr(s:remoteServName, 'mode()') ==# 'c'
      call remote_send(s:remoteServName, "\<C-U>".a:cmd."\<CR>")
      call s:WaitForDbgPrompt()
      if remote_expr(s:remoteServName, 'mode()') ==# 'c'
        call s:ShowRemoteContext()
      endif
    endif
  catch
    let v:errmsg = substitute(v:exception, '^[^:]\+:', '', '')
    call s:ShowRemoteError(v:exception, s:remoteServName)
  endtry
endfunction " }}}

function! s:WaitForDbgPrompt() " Throws remote exceptions. {{{
  sleep 100m " Minimum time.
  try
    if remote_expr(s:remoteServName, 'mode()') ==# 'c'
      return 1
    else
      try
        while 1
          sleep 1
          if remote_expr(s:remoteServName, 'mode()') ==# 'c'
            break
          endif
        endwhile
        return 1
      catch /^Vim:Interrupt$/
      endtry
    endif
    return 0
  catch
    let v:errmsg = substitute(v:exception, '^[^:]\+:', '', '')
    call s:ShowRemoteError(v:exception, s:remoteServName)
  endtry
endfunction " }}}

function! ParseContext(context) " {{{
    let mode = g:breakpts#BM_FUNCTION
    " FIXME: Get the function stack and make better use of it.
    let name = ''
    let sr = substitute(a:context,
          \ '^function \%('.s:FUNC_NAME_PAT.'\.\.\)*\('.s:FUNC_NAME_PAT.
          \ '\)'.s:str_in_line.'\(\d\+\).*$',
          \ 'let name = ''\1'' | let lineNo = ''\2''', '')
    if sr != a:context
      exec sr
    endif
    if name == ''
      let ss = substitute(a:context,
            \ '^\(.\+\)'.s:str_in_line.'\(\d\+\).*$',
            \ 'let name = ''\1'' | let lineNo = ''\2''', '')
      exec ss
      let mode = g:breakpts#BM_SCRIPT
    endif
    return [mode, name, lineNo]
endfunction " }}}

function! s:ShowRemoteContext() " {{{
  let context = s:GetRemoteContext()
  if context != ''
    let [mode, name, lineNo] = ParseContext(context)
    if name != ''
      let currentBufNr = bufwinnr("%")
      if name != s:GetListingName()
        call s:Browser(0, mode, '', name)
      endif
      let s:curLineInCntxt = lineNo
      let s:curNameInCntxt = name
      call MarkRemoteLine()
      let bufLocalNr = bufwinnr(g:BreakPts_locals_title)  
      if bufLocalNr != -1
        call s:PrintLocals()
      endif
      noautocmd exec currentBufNr . 'wincmd w'
    else
      let s:curNameInCntxt = ''
      let s:curLineInCntxt = ''
    endif
  endif
endfunction " }}}

function! MarkRemoteLine() 
  if s:curLineInCntxt != ''
    "On functions with line continuation, lines have gaps
    "so search in first line number if that line is equal to one searched
    "if it is above stay on previous line
    let pos = 3 "first line is 1 so start at 3
    let currentpos = 1
    while currentpos <= s:curLineInCntxt
      let line = getline(pos)
      let currentpos = str2nr(substitute(line, '\(\d\+\).*', '\1',''))
      if currentpos >= s:curLineInCntxt
        break
      endif
      let pos = pos + 1
    endwhile
    exec pos
    if winline() == winheight(0)
      normal! z.
    endif
    call s:MarkCurLineInCntxt(pos)
  endif
endfunction " }}}

function! s:GetRemoteContext() " {{{
  try
    if s:remoteServName !=# '.' &&
          \ remote_expr(s:remoteServName, 'mode()') ==# 'c'
      " FIXME: Assume C-U is not mapped.
      call remote_send(s:remoteServName, "\<C-U>exec ".
            \ "breakpts#GenContext()\<CR>")
      sleep 100m " FIXME: Otherwise the var is not getting updated.
      " WHY: if the remote vim crashes in this call, no exception seems to get
      "   generated.
      return remote_expr(s:remoteServName, 'g:BPCurContext')
    endif
  catch
    let v:errmsg = substitute(v:exception, '^[^:]\+:', '', '')
    call s:ShowRemoteError(v:exception, s:remoteServName)
  endtry
  return ''
endfunction " }}}

function! s:Open() " {{{
  let browserMode = s:GetBrowserMode()
  if browserMode == g:breakpts#BM_SCRIPTS
    let curScript = s:GetScript()
    let bufNr = bufnr(curScript)
    let winNr = bufwinnr(bufNr)
    if winNr != -1
      exec winNr . 'wincmd w'
    else
      if winbufnr(2) == -1
        split
      else
        wincmd p
      endif
      if bufNr != -1
        exec 'edit #'.bufNr
      else
        exec 'edit '.curScript
      endif
    endif
  else
    call s:DoAction()
  endif
endfunction " }}}

" BPBreak {{{
let s:breakIf = ''
function! breakpts#BreakIfCount(skipCount, expireCount, cond, offset)
  if s:breakIf == ''
    let s:breakIf = genutils#ExtractFuncListing(s:myScriptId.'_BreakIf', 0, 0)
  endif
  let expr = s:breakIf
  let expr = substitute(expr, '<offset>', a:offset, 'g')
  let expr = substitute(expr, '<skipCount>', a:skipCount, 'g')
  let expr = substitute(expr, '<expireCount>', a:expireCount, 'g')
  let expr = substitute(expr, '<cond>', a:cond, 'g')
  return expr
endfunction

function! breakpts#BreakCheckHitCount(breakLine, skipCount, expireCount)
  if !has_key(s:bpCounters, a:breakLine)
    let bpCount = 0
  else
    let bpCount = s:bpCounters[a:breakLine]
  endif
  let bpCount = bpCount + 1
  let s:bpCounters[a:breakLine] = bpCount
  if bpCount > a:skipCount && (a:expireCount < 0 || bpCount <= a:expireCount)
    return 1
  else
    return 0
  endif
endfunction

function! breakpts#Break(offset)
  return breakpts#BreakIfCount(-1, -1, 1, a:offset)
endfunction

function! breakpts#BreakIf(cond, offset)
  return breakpts#BreakIfCount(-1, -1, a:cond, a:offset)
endfunction

function! breakpts#DeBreak(offset)
  return breakpts#BreakIfCount(-1, -1, 0, a:offset)
endfunction

function! s:_BreakIf()
  try
    throw ''
  catch
    let __breakLine = v:throwpoint
  endtry
  if __breakLine =~# '^function '
    let __breakLine = substitute(__breakLine,
          \ '^function \%(\%(\k\|[<>]\|#\)\+\.\.\)*\(\%(\k\|[<>]\|#\)\+\), ' .
          \     s:str_line.'\s\+\(\d\+\)$',
          \ '\="func " . (submatch(2) + <offset>) . " " . submatch(1)', '')
  else
    let __breakLine = substitute(__breakLine,
          \ '^\(.\{-}\), '.s:str_line.'\s\+\(\d\+\)$',
          \ '\="file " . (submatch(2) + <offset>) . " " . submatch(1)', '')
  endif
  if __breakLine != ''
    silent! exec "breakdel " . __breakLine
    if <cond> && breakpts#BreakCheckHitCount(__breakLine, <skipCount>, <expireCount>)
      exec "breakadd " . __breakLine
    endif
  endif
  unlet __breakLine
endfunction
" BPBreak }}}

" Context {{{
" Generate the current context into g:BPCurContext variable
let g:BPCurContext = ''
let s:genContext = ''
function! breakpts#GenContext()
  if s:genContext == ''
    let s:genContext = genutils#ExtractFuncListing(s:myScriptId.'_GenContext', 0, 0)
  endif
  return s:genContext
endfunction

function! s:_GenContext()
  try
    throw ''
  catch
    let g:BPCurContext = v:throwpoint
  endtry
endfunction
" Context }}}

function! breakpts#RuntimeComplete(ArgLead, CmdLine, CursorPos)
  return s:RuntimeCompleteImpl(a:ArgLead, a:CmdLine, a:CursorPos, 1)
endfunction

function! s:RuntimeCompleteImpl(ArgLead, CmdLine, CursorPos, smartSlash)
  return genutils#UserFileComplete(a:ArgLead, a:CmdLine, a:CursorPos, a:smartSlash, &rtp)
endfunction

function! breakpts#BreakAddComplete(ArgLead, CmdLine, CursorPos)
  let sub = strpart(a:CmdLine, 0, a:CursorPos)
  let cmdPrefixPat = '^\s*Breaka\%[dd]\s\+'
  if sub =~# cmdPrefixPat.'func\s\+'
    return substitute(genutils#GetVimCmdOutput('function'), '^\n\|function \([^(]\+\)([^)]*)'
          \ , '\1', 'g')
  elseif sub =~# cmdPrefixPat.'file\s\+'
    return s:RuntimeCompleteImpl(a:ArgLead, a:CmdLine, a:CursorPos, 0)
  else
    return "func\nfile\n"
  endif
endfunction

function! breakpts#BreakDelComplete(ArgLead, CmdLine, CursorPos)
  let brkPts = substitute(genutils#GetVimCmdOutput('breaklist'), '^\n', '', '')
  if brkPts !~ 'No breakpoints defined'
    return substitute(brkPts, '\s*\d\+\s\+\(func\|file\)\([^'."\n".
          \ ']\{-}\)\s\+line\s\+\(\d\+\)', '\1 \3 \2', 'g')
  else
    return ''
  endif
endfunction

function! breakpts#WinManagerRefresh()
  if s:myBufNum == -1
    let s:myBufNum = bufnr('%')
  endif
  let s:opMode = 'WinManager'
  call breakpts#BrowserRefresh(0)
endfunction
" Utilities }}}


" Navigation {{{
function! s:NavigateBack()
  call s:Navigate('u')
  if getline(1) == ''
    call s:NavigateForward()
  endif
endfunction


function! s:NavigateForward()
  call s:Navigate("\<C-R>")
endfunction


function! s:Navigate(key)
  call s:ClearSigns()
  let _modifiable = &l:modifiable
  setlocal modifiable
  normal! mt

  silent! exec "normal" a:key

  let &l:modifiable = _modifiable
  call s:MarkBreakPoints(s:GetListingName())

  if line("'t") > 0 && line("'t") <= line('$')
    normal! `t
  endif
endfunction
" Navigation }}}


" Restore cpo.
let &cpo = s:save_cpo
unlet s:save_cpo

" vim6:fdm=marker sw=2 et
