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

function! treesittervim#handle_syntax_nodes(nodes) abort
  if &l:syntax != ''
    let b:treesitter_syntax = &l:syntax
    let &l:syntax = ''
  endif
  let l:ln1 = b:treesitter_range[0] - b:treesitter_range[2] / 2
  let l:ln2 = b:treesitter_range[1] + b:treesitter_range[2] / 2
  call s:clear()
  let l:ln = 0
  for l:m in a:nodes
    let l:ln += 1
    if l:ln1 <= l:ln && l:ln <= l:ln2
      let l:col = 1
      let l:i = 0
      while l:i < len(l:m)
        let [l:c, l:s] = [l:m[l:i],l:m[l:i+1]]
        let l:i += 2
        try
          call prop_add(l:ln, l:col, {'length': l:s, 'type': l:c})
        catch
        endtry
        let l:col += l:s
      endwhile
    endif
  endfor
endfunction

function! treesittervim#handle_syntax(ch, msg) abort
  try
    let b:treesitter_nodes = json_decode(a:msg)
    call treesittervim#handle_syntax_nodes(b:treesitter_nodes)
  catch
    let b:treesitter_nodes = []
  endtry
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
    call ch_sendraw(s:ch, json_encode(['syntax', &filetype, l:lines]) . "\n", {'callback': 'treesittervim#handle_syntax'})
  catch
    echomsg v:exception
  endtry
endfunction

function! treesittervim#handle_version(ch, msg) abort
  try
    echomsg a:msg
  catch
  endtry
endfunc

function! treesittervim#version() abort
  try
    let l:lines = join(getline(1, '$'), "\n")
    call ch_sendraw(s:ch, json_encode(['version']) . "\n", {'callback': 'treesittervim#handle_version'})
  catch
    echomsg v:exception
  endtry
endfunction

function! treesittervim#handle_textobj(ch, msg) abort
  try
    "echomsg json_decode(a:msg)
    echomsg a:msg
  catch
  endtry
endfunc

function! treesittervim#textobj() abort
  try
    let l:lines = join(getline(1, '$'), "\n")
    call ch_sendraw(s:ch, json_encode(['textobj', &filetype, l:lines, '' . col('.'), '' . line('.')]) . "\n", {'callback': 'treesittervim#handle_textobj'})
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
  let l:range = [l:wininfo['topline'], l:wininfo['botline'], l:wininfo['height']]

  if a:update || empty(get(b:, 'treesitter_nodes', []))
    let b:treesitter_range = l:range
    let s:timer = timer_start(0, {t -> treesittervim#syntax() })
  else
    let l:cached_range = get(b:, 'treesitter_range', [-1, -1, -1])
    if l:cached_range == l:range
      return
    endif
    let b:treesitter_range = l:range
    let s:timer = timer_start(0, {t -> treesittervim#handle_syntax_nodes(b:treesitter_nodes) })
  endif
endfunction
