let s:server = fnamemodify(expand('<sfile>:h:h') . '/server/server', ':p')
if has('win32')
  let s:server = substitute(s:server, '/', '\\', 'g')
endif

function! s:prop_type_add(name, attr) abort
  if empty(prop_type_get(a:name))
    call prop_type_add(a:name, a:attr)
  endif
endfunction

call s:prop_type_add('tsv_2', {'highlight': 'Operator'})
call s:prop_type_add('tsv_3', {'highlight': 'Keyword'})
call s:prop_type_add('tsv_4', {'highlight': 'Identifier'})
call s:prop_type_add('tsv_5', {'highlight': 'SpecialChar'})
call s:prop_type_add('tsv_6', {'highlight': 'String'})
call s:prop_type_add('tsv_7', {'highlight': 'Number'})
call s:prop_type_add('tsv_8', {'highlight': 'Error'})
call s:prop_type_add('tsv_9', {'highlight': 'Comment'})

function treesittervim#handle(ch, msg) abort
  let l:ln = 0
  for l:m in json_decode(a:msg)
    let l:ln += 1
    let l:col = 1
    let l:i = 0
    while l:i < len(l:m)
      let [l:c, l:s] = [l:m[l:i],l:m[l:i+1]]
      let l:i += 2
      if l:c >= 2
        call prop_add(l:ln, l:col, {'length': l:s, 'type': 'tsv_' . l:c})
      endif
      let l:col += l:s
    endwhile
  endfor
endfunc

function! s:clear() abort
  for l:v in ['tsv_2', 'tsv_3', 'tsv_4', 'tsv_5', 'tsv_6', 'tsv_7', 'tsv_8', 'tsv_9']
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
