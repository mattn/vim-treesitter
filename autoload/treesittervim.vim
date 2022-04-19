let s:dir = expand('<sfile>:h:h')
let s:server = fnamemodify(s:dir . '/cmd/server/server', ':p')
if has('win32')
  let s:server = substitute(s:server, '/', '\\', 'g') . '.exe'
endif

let s:disabled = 0
function! s:start_server() abort
  if s:disabled
    augroup treesitter
      au!
    augroup END
    return 0
  endif

  if !executable(s:server)
    let l:dir = s:dir . '/cmd/server'
    if has('win32')
      let l:dir = substitute(l:dir, '/', '\\', 'g')
    endif
    let s:disabled = 1
    echohl WarningMsg | echomsg 'Building server...' | echohl None
    sleep 1
    let l:cwd = getcwd()
    try
      call chdir(l:dir)
      !go build
    catch
    finally
      call chdir(l:cwd)
    endtry
    if !executable(s:server)
      return 0
    endif
    let s:disabled = 0
  endif
  let s:job = job_start(s:server, {'noblock': 1})
  let s:ch = job_getchannel(s:job)
  return 1
endfunction

function! s:prop_type_add(name, attr) abort
  if empty(prop_type_get(a:name))
    call prop_type_add(a:name, a:attr)
  endif
endfunction

let s:syntax = ['TSAnnotation', 'TSAttribute', 'TSBoolean', 'TSCharacter', 'TSComment', 'TSConditional', 'TSConstBuiltin', 'TSConstMacro', 'TSConstant', 'TSConstructor', 'TSDanger', 'TSEmphasis', 'TSEnvironment', 'TSEnvironmentName', 'TSException', 'TSField', 'TSFloat', 'TSFuncBuiltin', 'TSFuncMacro', 'TSFunction', 'TSInclude', 'TSKeyword', 'TSKeywordFunction', 'TSKeywordOperator', 'TSKeywordReturn', 'TSLabel', 'TSLiteral', 'TSMath', 'TSMethod', 'TSNamespace', 'TSNone', 'TSNote', 'TSNumber', 'TSOperator', 'TSParameter', 'TSParameterReference', 'TSProperty', 'TSPunctBracket', 'TSPunctDelimiter', 'TSPunctSpecial', 'TSRepeat', 'TSStrike', 'TSString', 'TSStringEscape', 'TSStringRegex', 'TSStringSpecial', 'TSStrong', 'TSSymbol', 'TSTag', 'TSTagAttribute', 'TSTagDelimiter', 'TSText', 'TSTextReference', 'TSTitle', 'TSType', 'TSTypeBuiltin', 'TSURI', 'TSUnderline', 'TSVariableBuiltin', 'TSWarning']
for s:s in s:syntax
  call s:prop_type_add(s:s, {'highlight': s:s})
endfor
unlet s:s

function! treesittervim#handle(ch, msg) abort
  try
    let l:v = json_decode(a:msg)
    if l:v[0] == 'version'
      call s:handle_version(l:v[1])
    elseif l:v[0] == 'syntax'
      call s:handle_syntax(l:v[1])
    elseif l:v[0] == 'textobj'
      call s:handle_textobj(l:v[1])
    endif
  catch
  endtry
endfunction

function! treesittervim#redraw(range) abort
  if &l:syntax != ''
    let b:treesitter_syntax = &l:syntax
    let &l:syntax = ''
  endif

  call s:clear()
  for l:line in b:treesitter_proplines[a:range[0] : a:range[1]]
    for l:prop in l:line
      try
        call prop_add(l:prop.row, l:prop.col, l:prop.attr)
      catch
      endtry
    endfor
  endfor
endfunction

function! s:handle_syntax(value) abort
  let b:treesitter_proplines = a:value
  call treesittervim#redraw()
endfunc

function! s:clear() abort
  for l:v in s:syntax
    while 1
      let l:prop = prop_find({'type': l:v})
      if empty(l:prop)
        break
      endif
      call prop_remove(l:prop)
    endwhile
  endfor
endfunction

function! treesittervim#syntax() abort
  try
    let l:lines = join(getline(1, '$'), "\n")
    call ch_sendraw(s:ch, json_encode(['syntax', &filetype, l:lines]) . "\n", {'callback': 'treesittervim#handle'})
  catch
    echomsg v:exception
  endtry
endfunction

function! s:handle_version(value) abort
  try
    echomsg a:value
  catch
  endtry
endfunc

function! treesittervim#version() abort
  try
    let l:lines = join(getline(1, '$'), "\n")
    call ch_sendraw(s:ch, json_encode(['version']) . "\n", {'callback': 'treesittervim#handle'})
  catch
    echomsg v:exception
  endtry
endfunction

function! s:handle_textobj(value) abort
  try
    call cursor(a:value['start'].row+1, a:value['start'].column+1)
    normal v
    call cursor(a:value['end'].row+1, a:value['end'].column)
  catch
  endtry
endfunc

function! treesittervim#textobj() abort
  try
    let l:lines = join(getline(1, '$'), "\n")
    call ch_sendraw(s:ch, json_encode(['textobj', &filetype, l:lines, '' . (col('.')-1), '' . (line('.')-1)]) . "\n", {'callback': 'treesittervim#handle'})
  catch
    echomsg v:exception
  endtry
endfunction

let s:syntax_timer = 0
function! treesittervim#fire(update) abort
  if !exists('s:ch')
    if !s:start_server()
      return
    endif
  endif

  if a:update || empty(get(b:, 'treesitter_proplines', []))
    call timer_stop(s:syntax_timer)
    let s:syntax_timer = timer_start(0, {t -> treesittervim#syntax() })
  else
    let l:wininfo = getwininfo()[0]
    let l:range = [l:wininfo['topline'], l:wininfo['topline'] + l:wininfo['height']]
    let cache_range = get(b:, 'treesitter_range', [-1, -1])
    if l:range ==# l:cache_range
      return
    endif
    let b:treesitter_range = l:range
    call treesittervim#redraw(range)
  endif
endfunction
