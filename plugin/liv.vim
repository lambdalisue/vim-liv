" plugin/liv.vim — thin :Liv* command shell delegating to liv.bundler (Lua).
"
" This file is auto-loaded by BOTH editors from plugin/, so it is LEGACY Vim
" script on purpose: Neovim does not parse Vim 9 script. It only wires commands to
" liv.bundler.cli; the real logic stays in Lua. (Vim-only companions that run
" solely on Vim — e.g. lua/liv/std/_dispatch.vim — are Vim 9 script; this entry,
" which must load on Neovim too, cannot be.)
if exists('g:loaded_liv')
  finish
endif
let g:loaded_liv = 1

" :LivBundle <module>... [--source=rtp|path] [--from=dir] [--to=dir] --plugin=name
"   No args beyond modules uses the rtp source (resolve from &runtimepath).
command! -nargs=+ LivBundle call s:liv_bundle(<q-args>)

function! s:liv_bundle(args) abort
  call luaeval('require("liv.bundler.cli")._command(_A[1], _A[2])', [a:args, &runtimepath])
endfunction
