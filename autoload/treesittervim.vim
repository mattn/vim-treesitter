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

function! treesittervim#redraw() abort
  if &l:syntax != ''
    let b:treesitter_syntax = &l:syntax
    let &l:syntax = ''
  endif

  let l:ln1 = b:treesitter_range[0]
  let l:ln2 = b:treesitter_range[1]
  call s:clear()
  for l:prop in b:treesitter_props
    if l:ln1 <= l:ln && l:ln <= l:ln2
      try
        call prop_add(l:prop[0], l:prop[1], l:prop[2])
      catch
      endtry
    endif
  endfor
endfunction

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

function! s:handle_syntax(value) abort
  let l:props = []
  let l:ln = 0
  for l:m in a:values
    let l:ln += 1
    let l:col = 1
    let l:i = 0
    while l:i < len(l:m)
      let [l:c, l:s] = [l:m[l:i],l:m[l:i+1]]
      let l:i += 2
      call add(l:props, [l:ln, l:col, {'length': l:s, 'type': l:c}])
      let l:col += l:s
    endwhile
  endfor
  let b:treesitter_props = l:props
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
    call cursor(a:value['start'].row+1, a:value['start'].column)
    normal v
    call cursor(a:value['end'].row+1, a:value['end'].column+1)
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

let s:timer = 0
function! treesittervim#fire(update) abort
  if !exists('s:ch')
    if !s:start_server()
      return
    endif
  endif

  call timer_stop(s:timer)
  let l:wininfo = getwininfo()[0]
  let l:v = [l:wininfo['topline'], l:wininfo['height']]
  let l:range = [l:v[0]-l:v[1], l:v[0]+l:v[1]+l:v[1]]

  if a:update || empty(get(b:, 'treesitter_props', []))
    let s:timer = timer_start(0, {t -> treesittervim#syntax() })
  else
    let b:treesitter_range = l:range
    let s:timer = timer_start(0, {t -> treesittervim#redraw() })
  endif
endfunction
