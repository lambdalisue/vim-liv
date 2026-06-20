---
name: liv-plugin-authoring
description: Conventions for writing a liv plugin — one Lua source that runs on both Vim 9 (+lua) and Neovim. Use when creating or editing code in a liv-based plugin, deciding where a module belongs (liv.core/liv.std/liv.lua), or reviewing liv code for the framework's hard rules (own-the-contract naming, 1-based ranges, Lua 5.1 dialect, string-literal require, barrel/leaf splits).
---

# Writing a liv plugin

liv lets you write a **single Lua source** that runs on **both Vim 9 (`+lua`) and
Neovim**, where end users install only your plugin — every dependency is vendored
in by `liv.bundler`. Target the constrained side (Vim `+lua`, Lua 5.1); Neovim
(LuaJIT) is satisfied naturally.

## Six namespaces, one placement rule

Runtime (vendored into the consumer plugin):

- **`liv.core`** — the seam. Owns value **marshaling** and the **vimscript** seam
  (`call`/`eval`/`cmd`). The only place that marshals and the only caller of
  `vim.call`/`vim.eval`/`vim.command`. Keep it minimal; never add per-feature APIs.
- **`liv.std`** — liv's own **editor-dependent** cross-editor API, named by purpose
  (`liv.std.buffer`, `liv.std.process`, …). Degrades via `liv.std.has`.
- **`liv.lua`** — **editor-independent** pure Lua (`liv.lua.compat`, `liv.lua.async`,
  `liv.lua.path`, …). Never touches the editor, not even `liv.core`.

Dev tools (pure Lua, **never vendored**): `liv.bundler`, `liv.tester`,
`liv.generator`.

**Placement:** needs the editor to function → `liv.std`; pure computation →
`liv.lua`; raw editor primitive → `liv.core` (rare). Never flatten std and lua
behind one re-export — the namespace must keep advertising whether a module is
editor-dependent (can degrade) or pure (guaranteed).

## Hard rules

- **Own the contract.** Do NOT mimic Neovim's API names or shapes (`nvim_*`,
  `vim.api`, `extmark`, `vim.uv`, `vim.schedule`, `vim.keymap.set`). "Similar but
  different" breeds silent bugs. Use liv's own vocabulary. Domain words
  (buffer/window/tabpage/option/autocmd) are fine — different *behavior* gets a
  different *name*.
- **Conventions (all APIs follow them):**
  - Ranges are **1-based, inclusive** (NOT Neovim's 0-based/exclusive).
  - **Handles** are integer ids; `0` or `nil` means current.
  - **Positions** are `{line, col}`, 1-based.
  - **Failures** raise via `error()` (pcall-able); async errors propagate through `await`.
  - **Callbacks** are plain Lua functions passed directly — both editors keep them
    alive, no manual registry. (The one exception is Vim's string-only contexts;
    handled internally by a `_vim` backend, never exposed.)
- **Lua 5.1-compatible dialect.** Vim may link Lua 5.1–5.4 or LuaJIT; the floor is
  5.1. Forbidden: `goto`/labels (5.2+), integer division `//` and bitwise
  `& | ~ << >>` (5.3+), `<close>`/`<const>` (5.4), reliance on `math.type` /
  integer subtypes. Use **`liv.lua.compat`** for bit ops, `unpack`,
  `package.loaders`, removed stdlib fns. Detect integrality with `n % 1 == 0`.
- **`require` must use a string literal.** The bundler analyzes requires
  statically. Declare dynamic deps and non-`.lua` companions (Vim 9 `.vim`, data
  files) in a dependency manifest beside the module.
- **Backend selection happens once at import.** A `liv.std` area is
  `area/init.lua` selecting `_nvim` or `_vim` ONCE (a factory
  `function(core) return {...} end`). Never branch on `is_nvim` per call.
- **On Neovim, prefer the native Lua API** (`vim.api.*`, `vim.uv`, `vim.json`) over
  a vimscript builtin when it differs observably — but cross editor *values*
  through `core.marshaled`, never hand-rolled.

## Module granularity (barrel / leaf)

The bundler closure is **file-grained** (follows literal `require`s, vendors whole
files, no per-function dead-code elimination). So the split between files is what
determines bundle size.

- **One-way deps: barrel → leaf only.** A barrel (`init.lua`) MAY require its
  leaves for a convenience/dispatch API. A **leaf MUST NOT require its barrel** —
  that re-pulls the whole family. An internal consumer of one leaf requires THAT
  leaf directly (e.g. `liv.lua.png.decode` requires `liv.lua.zlib.inflate`, not
  `liv.lua.zlib`).
- **Consumer-importable leaves get public names** (no leading `_`). `_` is for
  truly-internal shared helpers (`liv.lua.png._crc`).
- New multi-codec / multi-algorithm families start **leaf-split + thin barrel**.
- **Question aggregator/factory structures, but MEASURE before splitting** — split
  only when per-function code is substantial AND the shared core is not dominant
  AND a real consumer uses a subset. Over-splitting (file count, `require`
  overhead, lost cohesion) is itself a cost.

## TDD

Write the failing test first. **L1** (`spec/`, no editor, plain `lua`/`busted`) for
pure logic; **L3** (`test/`, real Vim `+lua` AND Neovim, headless) for `liv.core`
and each backend. Inject `liv.core` (and async `schedule`) so tests can substitute
fakes; avoid global state. See the `liv-tester` skill.

## Documentation layering

Code → How, Tests → What, Commits → Why, Comments → Why not.

## Deeper reference

Normative specs live in the vim-liv repo under `.claude/specs/`:
`0001-overview`, `0002-principles`, `0003-architecture`, `0004-core`,
`0005-marshaling`, `0006-std`, `0007-async`. Related skills: `liv-library-api`,
`liv-bundler`, `liv-tester`.
