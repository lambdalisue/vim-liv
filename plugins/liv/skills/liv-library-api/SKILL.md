---
name: liv-library-api
description: Reference for the liv runtime API a plugin author consumes — liv.core (call/eval/cmd/marshaled/is_nvim + marshaling), the liv.std.* editor-dependent modules (buffer, window, process, task, fs, fetch, ui, option, variable, autocmd, mapping, keys, highlight, sign, text, log, has, …) and the liv.lua.* pure modules (compat, async, path, uri, argument, base64, hash, color, png/zlib/msgpack, …). Use when calling or looking up a liv API, choosing the right module, or checking capability/degradation.
---

# liv runtime API

The runtime surface a liv plugin calls. All modules follow liv's conventions:
ranges **1-based inclusive**, integer handles (`0`/`nil` = current), positions
`{line, col}`, failures via `error()` (pcall-able). Get them with a string-literal
`require` (e.g. `local buffer = require("liv.std.buffer")`).

## `liv.core` — the seam

The minimal primitive over the editor + value marshaling. You rarely call it
directly (use `liv.std`), but it exposes:

- `call(name, ...)` — call a vimscript function by name (dynamic dispatch).
- `eval(expr)` — evaluate a vimscript expression.
- `cmd(command)` — run ONE Ex command (use `liv.std.exec` for a block).
- `marshaled(ref)` — wrap a native callable (`vim.fn.X` / `vim.api.X`) so its
  values marshal across the editor boundary. Used by `_nvim`/`_vim` backends.
- `is_nvim` — backend flag (selected once at import; do not branch per call).
- Marshaling: `NIL`, `list`, `dict`, `empty_dict`, `is_list`, `is_dict`,
  `to_editor`, `from_editor`. Both editors return the same plain Lua values.

## `liv.std.*` — editor-dependent API (degrades via `has`)

| module | what it does (representative API) |
| --- | --- |
| `buffer` | `lines(buf,first,last)` / `set_lines(...)` / `create(opts)` / `wipe` / `name` / `count` / `valid` / `with(buf,fn)` / `modifiable(buf,fn)` |
| `window` | `current` / `all` / `buffer(win)` / `valid` / `cursor` / `set_cursor` / `focus` / `close` / `size` |
| `tabpage` | `current` / `all` / `windows(tab)` |
| `option` | `option.<g\|b\|w\|l>.get(name,target?)` / `.set(name,value,target?)` / `.reset(name)` (+ property access `option.g.expandtab`) |
| `variable` | `variable.<g\|b\|w\|t\|v\|r\|env>.get/set` (g:/b:/w:/t:/v: vars, `r` registers, `env` `$VAR`) |
| `function` | `function.<name>(...)` — typed vimscript builtins (LuaLS-typed; generated) |
| `mapping` | `set(modes,lhs,opts?,rhs)->sub` / `sub.off()` / `del` / `get` / `list` |
| `keys` | `encode(notation)->bytes` / `feed(keys,opts?)` / `send(keys,opts?)` |
| `command` | `define(name,opts?,handler)->sub` / `sub.off()` / `remove` |
| `autocmd` | `on(events,{pattern,group,once},handler)->sub` / `sub.off()` / `trigger` / `list` |
| `process` | `system(cmd,opts?)` (async one-shot) / `run(cmd,opts?)` (sync) / `open(cmd,{on_stdout,...})` (streaming; `has("process.stream")`) |
| `task` | async runner facade: `run(afn,on_done)` / `await` / `wrap` / `schedule` / `sleep(ms)` / `block(handle,timeout)` |
| `fs` | `read`/`write`/`stat`/`scandir`/`exists`/`is_dir`/`is_file`/`mkdir`/`remove`/`copy`/`rename`/`touch`/`tempname`/`expand`/`find_upward`/`walk` |
| `fetch` | `fetch(url,opts)->response` (awaitable HTTP(S); `has("fetch")`, HTTPS via curl→wget) |
| `ui` | `select(items,opts?,handler)` / `prompt(opts?,handler)` / `notify(msg,level)` |
| `exec` | `exec(source)` — run a multi-line vimscript block (string or line array) |
| `log` | `new({name,level,console,file})->logger` ; `logger.<trace\|debug\|info\|warn\|error>(...)` / `set_level` |
| `callback` | `function_name(handler)->name` / `named(handler)->name` / `release(name)` — bind a Lua fn to a Vim-callable name |
| `popup` | `open(content,opts)->win` / `close` / `move` / `resize` |
| `mark` | `place(buf,line,{virt_text,hl,...})->id` / `range(...)` (`has("mark.range")`) / `remove` / `clear` |
| `sign` | `define(name,{text,...})` / `place(buf,line,name,{group,priority})->id` / `remove` / `clear` |
| `highlight` | `set(name,{fg,bg,sp,bold,italic,...})` (`has("highlight")`; needs `'termguicolors'`) |
| `cursor` | `hide()` / `show()` (`has("cursor.hide")`) |
| `text` | `width(str)` / `truncate` / `pad` / `align` / `wrap` (display-column aware) |
| `json` | `encode(v)` / `decode(s)` |
| `hash` | `sha256(s)` / `md5(s)` / `sha1(s)` (lowercase hex) |
| `bufname` | `format({scheme,expr,params?,fragment?})` / `parse(string)` (codec) |
| `image` | `place({line,col},src,opts)->id` / `update` / `remove` (experimental; `has("image")`) |
| `has` | `liv.std.has(feature)` — capability detection (see below) |

## `liv.lua.*` — pure Lua (editor-independent, L1-testable)

`compat` (Lua 5.1 shim + bit ops), `async` (coroutine engine + combinators
`gather`/`select`; `schedule` injected), `path` (posix/unc flavours), `uri`
(percent/url/query leaves), `argument` (CLI parse/format), `base64`, `hash`,
`color`, `text`, `log`, `http`, `png`, `zlib`, `msgpack`, `value`. These never
touch the editor and depend only on other `liv.lua` modules — safe to depend on
with no backend matrix. Import the specific **leaf** you need (e.g.
`require("liv.lua.async")`), not a barrel, to keep bundles small.

## Capability & graceful degradation

Power features Vim lacks (treesitter, lsp, true libuv) are NOT in the contract.
Branch intentionally with `liv.std.has(feature)` — e.g. `has("async")`,
`has("fetch")`, `has("fetch.form")`, `has("process.stream")`, `has("highlight")`,
`has("mark.range")`, `has("mark.virt_text")`, `has("cursor.hide")`,
`has("popup.border")`, `has("image")`. In-contract base features work on both
editors; never fail silently.

## Deeper reference

vim-liv repo specs: `.claude/specs/0004-core.md`, `0005-marshaling.md`,
`0006-std.md`, `0007-async.md`. Related skill: `liv-plugin-authoring`. The actual
module list is `lua/liv/std/` and `lua/liv/lua/` in the repo.
