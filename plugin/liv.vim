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

"   :LivAdd <module>... [--source=rtp|path|git] [--from=...] [--ref=...] [--to=...] --plugin=name
"                             add modules to the bundle (union with the lockfile)
"   :LivUpdate [module...]    re-vendor (rebuild from the lockfile when no args)
"   :LivCheck                 report drift / missing vs the lockfile (read-only)
"   :LivRemove <module>...    drop modules and now-unused deps
command! -nargs=+ LivAdd    call s:liv('add',    <q-args>)
command! -nargs=* LivUpdate call s:liv('update', <q-args>)
command! -nargs=* LivCheck  call s:liv('check',  <q-args>)
command! -nargs=+ LivRemove call s:liv('remove', <q-args>)

function! s:liv(cmd, args) abort
  call luaeval('require("liv.bundler.cli")._command(_A[1], _A[2], _A[3])', [a:cmd, a:args, &runtimepath])
endfunction
