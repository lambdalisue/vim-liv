# 0003 — Architecture

## Monorepo, six namespaces

One repository `vim-liv` (itself a Vim/Neovim plugin) hosting:

| namespace | role | vendored? | editor-dependent? |
| --- | --- | --- | --- |
| `liv.core` | seam over the editor + value marshaling | yes | yes |
| `liv.std` | editor-**dependent** cross-editor API (buffer/window/process/…) | yes | yes (via core) |
| `liv.lua` | editor-**independent** pure-Lua modules (compat/async/path/…) | yes | **no** |
| `liv.bundler` | build-time bundler (dev tool) | **no** | no (pure Lua; `rtp` source reads `&runtimepath`) |
| `liv.tester` | cross-editor test framework + runner (dev tool) | **no** | no (pure Lua; spawns the editors for L3) |

The first three are the consumer **runtime** (vendored). The last two are
**dev-only tools**, never in a consumer's runtime require graph (so never
vendored). Each tool exposes one canonical `liv.<tool>.cli.main`, with a `bin/`
terminal entry and a `:Liv*` editor command as thin shims (see [0009](0009-commands.md)).

```
vim-liv/
  plugin/liv.vim            # registers :Liv* -> liv.<tool>.cli (thin wrappers)
  bin/liv-tester            # terminal entry -> liv.tester.cli  (bin/liv-bundler: planned)
  bin/liv-generator         # terminal entry -> liv.generator   (typed-wrapper codegen)
  lua/liv/
    core/                   # liv.core.*    (seam; centralizes value marshaling + call/eval/cmd)
    std/                    # liv.std.*     (editor-dependent API; via core only)
    lua/                    # liv.lua.*     (editor-independent pure Lua)
      compat.lua            #   liv.lua.compat  (Axis A shim)
      async/                #   liv.lua.async   (pure coroutine engine)
      path/                 #   liv.lua.path    (posix/unc flavours)
      msgpack/              #   liv.lua.msgpack (pure msgpack codec; streaming)
      http/                 #   liv.lua.http    (pure HTTP message parser)
      zlib/                 #   liv.lua.zlib    (pure DEFLATE inflate/deflate)
      png/                  #   liv.lua.png     (pure PNG codec; on liv.lua.zlib)
      hash/                 #   liv.lua.hash    (pure md5/sha1/sha256 + hmac)
      base64.lua            #   liv.lua.base64  (pure RFC 4648 base64 + url-safe)
      argument.lua          #   liv.lua.argument (command-arg parser: ++opt/--flag/rest)
      color.lua             #   liv.lua.color   (pure RGB/HSL/hex/xterm-256 color math)
    tester/                 # liv.tester.*  (test framework + cli; never vendored)
    bundler/                # liv.bundler.* (tool; never vendored)
    generator/              # liv.generator.* (typed-wrapper codegen; never vendored)
  spec/                     # L1 (no real editor; run in-process)
  test/                     # L3 (real Vim + Neovim, headless)
  .claude/specs/
```

## Where does a module go? (placement rule)

The everyday author surface is effectively **two** namespaces — `liv.std` and
`liv.lua` — with `liv.core` reserved as a rarely-used escape hatch. Decide by a
single question:

- **Does it need the editor to function?** → `liv.std` (a purpose-named,
  editor-dependent module; may degrade / be gated by `liv.std.has`, see
  [0006](0006-std.md)).
- **Is it pure computation?** → `liv.lua` (deterministic on every host, unit
  testable, safe to depend on from a library with no backend matrix).
- **Is it a raw editor primitive?** → `liv.core` (the seam; rare, advanced).

A module that *could* be written in pure Lua but whose correct/fast
implementation would be heavy or fragile — while both editors already ship a
solid native function — belongs in `liv.std` with native backends instead (e.g.
`liv.std.json` uses `vim.json` / `json_encode`). When a module lands in `liv.std`
for this reason rather than a hard editor requirement, **state that reason in the
module** (a note explaining "native is preferred over a heavy pure reimpl").

This split is deliberate honesty: the namespace tells you the risk profile —
`liv.std.*` can vary across editors, `liv.lua.*` cannot. **Do not** flatten the
two behind a single re-export; that would re-hide editor-dependence (the same
hazard P4 rejects for the global `vim` table).

## Layering

- A consumer plugin's runtime require graph reaches `liv.std.*`, `liv.lua.*`, and
  `liv.core` (seam) only. It never reaches `liv.bundler.*`, so the bundler is
  **never vendored** (the bundler's own static analysis confirms this).
- `liv.core` owns **marshaling** and the **vimscript** seam (`call`/`eval`/`cmd`).
  `liv.std` `_vim` backends reach the editor through those; `liv.std` `_nvim`
  backends may call the Neovim native API directly (they only run on Neovim) but
  always via `core.marshaled`, so marshaling stays centralized (see
  [0004](0004-core.md)). No code outside core hand-rolls marshaling.
- `liv.lua` never touches the editor at all (not even `liv.core`); it depends only
  on other `liv.lua` modules.
- An editor-dependent `liv.std` module may build on a pure `liv.lua` engine (e.g.
  `liv.std` process/task modules wire editor leaves into `liv.lua.async`); a
  library author who wants to stay editor-independent depends on `liv.lua.async`
  directly.
- Pure-Lua utilities (Data.*, etc.) are NOT reinvented here; authors bundle
  existing Lua libraries via the bundler.

## Compatibility axes

Two orthogonal axes — keep them separate:

- **Axis A — Lua language/stdlib version** (5.1–5.4 / LuaJIT). Handled by the
  bundled **compat shim `liv.lua.compat`**; source is written in a 5.1-compatible
  dialect. Editor-independent. (See the lua-dialect guardrail.)
- **Axis B — host editor** (Vim vs Neovim). Split:
  - **B-1 mechanical marshaling** (userdata↔table, list/dict, NIL, bool, number)
    → `liv.core` (invariant; see [0005](0005-marshaling.md)).
  - **B-2 feature unification** (buffer/window/process/float/…) → `liv.std`
    (per-module backend selection; see [0006](0006-std.md)).

## Backend selection

Editor-touching `liv.std` modules select a backend **once at import**:

```lua
-- liv/std/buffer/init.lua
local core = require("...liv.core")
return core.is_nvim
  and require("...liv.std.buffer._nvim")  -- native fast path
  or  require("...liv.std.buffer._vim")   -- Lua over Vim builtins (default)
```

Both `require` targets are string literals, so the bundler includes both
backends; exactly one runs per session. Never branch on `is_nvim` per call.

`liv.lua` modules also select a flavour once at import where relevant (e.g.
`liv.lua.path` picks `posix`/`unc` from the platform separator), but that choice
is editor-independent — it depends on the OS, not on Vim vs Neovim.
