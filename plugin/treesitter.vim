augroup treesitter
  autocmd TextChanged * call treesittervim#apply()
  if exists('##TextChangedP')
    autocmd TextChangedP * call treesittervim#apply()
  endif
augroup END


