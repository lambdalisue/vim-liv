vim9script
# liv dispatch (Vim only) — lets Vim's string-only contexts (:command / :map /
# :autocmd rhs) call back into Lua. A Lua function passed to a Vim function is
# auto-converted to a Funcref that holds the Lua reference alive, so we store
# handlers by id and invoke them from the rhs. Auto-sourced on first reference to
# liv#std#dispatch#Register (etc.); the Lua side no longer :sources it.
#
# The handler registry is a SCRIPT-LOCAL var, so a vendored copy at a different
# autoload path (e.g. mate#vendor#liv#std#dispatch#) gets its OWN registry — the
# vendoring isolation that a single shared g: dict would defeat. Runtime-created
# forwarders (for -complete=customlist / omnifunc / a named Funcref) must be
# global to be reachable from string contexts AND Vim 9 forbids `#` in runtime
# function names (E1263), so they stay g:-scoped — but uniquely prefixed per
# bundle via FWD (derived from this script's own path) so they never collide.
# Vim 9 script (NOT legacy).

var registry = {handlers: {}, counter: 0}

# This script's own path, relative to its autoload/ root (e.g.
# "liv/std/dispatch.vim" or "mate/vendor/liv/std/dispatch.vim" for a vendored
# copy). Used to derive both the autoload call prefix and the unique g: forwarder
# prefix below, so every bundle self-isolates without the bundler rewriting names.
const SELF = substitute(expand('<script>'), '^.\{-}autoload[\\/]', '', '')
const STEM = substitute(SELF, '\.vim$', '', '')
# Autoload prefix to call this script's own functions from a runtime-built
# forwarder body, e.g. "liv#std#dispatch#".
const APREFIX = substitute(STEM, '[\\/]', '#', 'g') .. '#'
# g: forwarder prefix (no `#`; capital-led for Vim 9 `def g:`), e.g.
# "Liv_liv_std_dispatch_".
const FWD = 'Liv_' .. substitute(STEM, '[^a-zA-Z0-9]', '_', 'g') .. '_'

# Register a handler (a Funcref, typically a Lua function) and return its id.
export def Register(Fn: func): string
  registry.counter += 1
  const id = string(registry.counter)
  registry.handlers[id] = Fn
  return id
enddef

# Invoke the handler for `id` with the given args (called from an rhs string).
export def Invoke(id: string, ...args: list<any>): any
  return call(registry.handlers[id], args)
enddef

# Invoke an `<expr>` mapping handler and replace key-notation in its returned
# string with the actual termcodes, so a handler returning "<CR>"/"<Right>"
# produces the real keys (matching Neovim's replace_keycodes). Vim's `<expr>`
# rhs uses the returned string verbatim, so we convert here: every '<' is
# prefixed with a backslash and the string is eval'd as a double-quoted string
# (where "\<CR>" notation IS interpreted). Backslashes and quotes are escaped
# first so literal text round-trips unchanged.
export def ExprInvoke(id: string, ...args: list<any>): string
  const result = call(registry.handlers[id], args)
  if type(result) != v:t_string
    return ''
  endif
  var escaped = substitute(result, '\\', '\\\\', 'g')
  escaped = substitute(escaped, '"', '\\"', 'g')
  escaped = substitute(escaped, '<', '\\<', 'g')
  return eval('"' .. escaped .. '"')
enddef

# Drop a handler.
export def Unregister(id: string)
  if has_key(registry.handlers, id)
    remove(registry.handlers, id)
  endif
enddef

# Bind a uniquely-named g: Funcref VARIABLE to a partial of this script's Invoke
# curried with `id`, so calling it forwards to Invoke(id, ...) — for any arity,
# including zero. Returns the (g:-qualified) name. A variable (not a function),
# so it can be created from ANY context without E1263/E1126.
export def NamedRegister(id: string): string
  const key = FWD .. 'Named' .. id
  g:[key] = function(APREFIX .. 'Invoke', [id])
  return 'g:' .. key
enddef

# Command-line `customlist` completion bridge. `:command -complete=customlist`
# names a function called as Func(ArgLead, CmdLine, CursorPos); it cannot carry a
# bound handler id, so we expose a fixed-named global forwarder that forwards to
# the handler registered under `id`. Each command gets its own forwarder name
# (created on demand) so multiple commands coexist. Returns the bare name.
export def CompleteRegister(id: string): string
  const name = FWD .. 'Complete' .. id
  if !exists('*g:' .. name)
    execute join([
      'def! g:' .. name .. '(ArgLead: string, CmdLine: string, CursorPos: number): list<string>',
      '  return ' .. APREFIX .. 'Invoke(' .. string(id) .. ', ArgLead, CmdLine, CursorPos)',
      'enddef',
    ], "\n")
  endif
  return name
enddef

# Generic two-argument forwarder bridge. Some string-valued options name a
# function called as Func(a, b) — notably 'omnifunc'/'completefunc', invoked as
# Func(findstart, base). Such an option cannot carry a bound handler id, so we
# expose a fixed-named global forwarder that forwards to the handler registered
# under `id`. Returns the bare name (without the g: sigil) so it can be assigned
# to a buffer-local option directly.
export def FuncRegister(id: string): string
  const name = FWD .. 'Func' .. id
  if !exists('*g:' .. name)
    execute join([
      'def! g:' .. name .. '(a: any, b: any): any',
      '  return ' .. APREFIX .. 'Invoke(' .. string(id) .. ', a, b)',
      'enddef',
    ], "\n")
  endif
  return name
enddef
