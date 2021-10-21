let s:server = fnamemodify(expand('<sfile>:h:h') . '/server/server', ':p')
if has('win32')
  let s:server = substitute(s:server, '/', '\\', 'g')
endif

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

function! treesittervim#handle_nodes(nodes) abort
  if &l:syntax != ''
    let b:treesitter_syntax = &l:syntax
    let &l:syntax = ''
  endif
  call s:clear()
  let l:info = getwininfo()[0]
  let l:ln = 0
  for l:m in a:nodes
    let l:ln += 1
    let l:col = 1
    let l:i = 0
    while l:i < len(l:m)
      let [l:c, l:s] = [l:m[l:i],l:m[l:i+1]]
      let l:i += 2
      try
        if l:info['topline']-100 <= l:ln && l:ln <= l:info['botline']+100
          call prop_add(l:ln, l:col, {'length': l:s, 'type': l:c})
        endif
      catch
      endtry
      let l:col += l:s
    endwhile
  endfor
endfunction

function! treesittervim#handle(ch, msg) abort
  let b:treesitter_nodes = json_decode(a:msg)
  call treesittervim#handle_nodes(b:treesitter_nodes)
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

let s:job = job_start(s:server, {'noblock': 1})
let s:ch = job_getchannel(s:job)

function! treesittervim#apply() abort
  try
    let l:lines = join(getline(1, '$'), "\n")
    if 0 && len(l:lines) >= get(b:, 'treesittervim_max_bytes', 50000)
      let l:syntax = get(b:, 'treesitter_syntax', '')
      if !empty(l:syntax)
        let &l:syntax = l:syntax
        let b:treesitter_syntax = ''
        call s:clear()
      endif
      return
    endif
    call ch_sendraw(s:ch, json_encode([&filetype, l:lines]) . "\n", {'callback': 'treesittervim#handle'})
  catch
    echomsg v:exception
  endtry
endfunction

let s:timer = 0
function! treesittervim#fire(update) abort
  call timer_stop(s:timer)
  if a:update || empty(get(b:, 'treesitter_nodes', []))
    let s:timer = timer_start(0, {t -> treesittervim#apply() })
  else
    let s:timer = timer_start(0, {t -> treesittervim#handle_nodes(b:treesitter_nodes) })
  endif
endfunction
