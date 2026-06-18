vim9script
# liv dispatch (Vim only) — lets Vim's string-only contexts (:command / :map /
# :autocmd rhs) call back into Lua. A Lua function passed to a Vim function is
# auto-converted to a Funcref that holds the Lua reference alive, so we store
# handlers by id and invoke them from the rhs. The registry is a single global
# dict shared across vendored liv copies; ids are globally unique, so there is no
# collision. This is Vim 9 script (NOT legacy Vim script).

if exists('g:LivDispatch')
  finish
endif

g:LivDispatch = {handlers: {}, counter: 0}

# Register a handler (a Funcref, typically a Lua function) and return its id.
def g:LivRegister(Fn: func): string
  g:LivDispatch.counter += 1
  const id = string(g:LivDispatch.counter)
  g:LivDispatch.handlers[id] = Fn
  return id
enddef

# Invoke the handler for `id` with the given args (called from an rhs string).
def g:LivInvoke(id: string, ...args: list<any>): any
  return call(g:LivDispatch.handlers[id], args)
enddef

# Invoke an `<expr>` mapping handler and replace key-notation in its returned
# string with the actual termcodes, so a handler returning "<CR>"/"<Right>"
# produces the real keys (matching Neovim's replace_keycodes). Vim's `<expr>`
# rhs uses the returned string verbatim, so we convert here: every '<' is
# prefixed with a backslash and the string is eval'd as a double-quoted string
# (where "\<CR>" notation IS interpreted). Backslashes and quotes are escaped
# first so literal text round-trips unchanged.
def g:LivExprInvoke(id: string, ...args: list<any>): string
  const result = call(g:LivDispatch.handlers[id], args)
  if type(result) != v:t_string
    return ''
  endif
  var escaped = substitute(result, '\\', '\\\\', 'g')
  escaped = substitute(escaped, '"', '\\"', 'g')
  escaped = substitute(escaped, '<', '\\<', 'g')
  return eval('"' .. escaped .. '"')
enddef

# Drop a handler.
def g:LivUnregister(id: string)
  if has_key(g:LivDispatch.handlers, id)
    remove(g:LivDispatch.handlers, id)
  endif
enddef

# Command-line `customlist` completion bridge. `:command -complete=customlist`
# names a function called as Func(ArgLead, CmdLine, CursorPos); it cannot carry a
# bound handler id, so we expose a fixed-named function that forwards to the Lua
# handler registered under `id`. Each command gets its own forwarder name
# (g:LivComplete{id}) created on demand so multiple commands coexist.
def g:LivCompleteRegister(id: string): string
  const name = 'LivComplete' .. id
  if !exists('*g:' .. name)
    execute join([
      'def! g:' .. name .. '(ArgLead: string, CmdLine: string, CursorPos: number): list<string>',
      '  return g:LivInvoke(' .. string(id) .. ', ArgLead, CmdLine, CursorPos)',
      'enddef',
    ], "\n")
  endif
  return name
enddef

# Generic two-argument forwarder bridge. Some string-valued options name a
# function called as Func(a, b) — notably 'omnifunc'/'completefunc', invoked as
# Func(findstart, base). Such an option cannot carry a bound handler id, so we
# expose a fixed-named function that forwards to the Lua handler registered under
# `id`. Each gets its own forwarder name (g:LivFunc{id}) created on demand so
# multiple handlers coexist. Returns the bare name (without the g: sigil) so it
# can be assigned to a buffer-local option directly.
def g:LivFuncRegister(id: string): string
  const name = 'LivFunc' .. id
  if !exists('*g:' .. name)
    execute join([
      'def! g:' .. name .. '(a: any, b: any): any',
      '  return g:LivInvoke(' .. string(id) .. ', a, b)',
      'enddef',
    ], "\n")
  endif
  return name
enddef
