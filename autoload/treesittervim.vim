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

function treesittervim#handle(ch, msg) abort
  let l:ln = 0
  for l:m in json_decode(a:msg)
    let l:ln += 1
    let l:col = 1
    let l:i = 0
    while l:i < len(l:m)
      let [l:c, l:s] = [l:m[l:i],l:m[l:i+1]]
      let l:i += 2
      if index(s:syntax, l:c) != -1
        call prop_add(l:ln, l:col, {'length': l:s, 'type': l:c})
      endif
      let l:col += l:s
    endwhile
  endfor
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

let s:job = job_start(s:server, {})
let s:ch = job_getchannel(s:job)

function! treesittervim#apply() abort
  call s:clear()
  call ch_sendraw(s:ch, json_encode([&filetype, join(getline(1, '$'), "\n")]) . "\n", {'callback': "treesittervim#handle"})
endfunction
