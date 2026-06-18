# vim-liv — project instructions for Claude

This is an OSS project. **All in-repo artifacts are written in English**: source
code, comments, log/error messages, commit messages, PR titles/bodies, issue
titles/bodies, branch names, and docs. (Conversation with the maintainer may be
in Japanese, but artifacts stay English.)

## What this project is

A framework for writing Lua plugins that run on **both Vim 9 (`+lua`) and
Neovim**, where installing only the consumer plugin suffices (deps are bundled).

Read [`docs/specs/`](docs/specs/) before non-trivial work — it is the normative
source of truth. Start with `docs/specs/0001-overview.md`.

## Architecture (six namespaces, one monorepo)

Runtime (vendored into consumer plugins):
- `liv.core` — invariant seam over the editor + value marshaling. The **only**
  module allowed to touch `vim.*`. (Rare escape hatch for authors.)
- `liv.std` — **editor-dependent** cross-editor API (buffer/window/process/…).
  Touches the editor **only via `liv.core`**. Named by purpose.
- `liv.lua` — **editor-independent** pure-Lua modules (`liv.lua.compat`,
  `liv.lua.async`, `liv.lua.path`, …). Never touches the editor.

Dev tools (pure Lua; **never vendored** — not in a consumer's runtime require graph):
- `liv.bundler` — build-time bundler.
- `liv.tester` — cross-editor test framework + runner (`bin/liv-tester`).
- `liv.generator` — build-time codegen of typed editor-API wrappers (`liv.std.fn`,
  `liv.std.option`) + LuaLS annotations from pinned Vim/Neovim docs (`bin/liv-generator`).

Each tool's canonical entry is `liv.<tool>.cli.main`; `bin/` and `:Liv*` are thin
shims. Placement rule: needs the editor → `liv.std`; pure computation →
`liv.lua`; raw primitive → `liv.core`. Don't flatten std/lua behind one re-export.

## Hard rules

- **Own the contract.** Do NOT mimic Neovim's API names or shapes
  (`nvim_*`, `vim.api`, `extmark`, `vim.uv`). "Similar but different" misleads.
  Use liv's own vocabulary; domain words (buffer/window/option) are fine.
- **Conventions:** ranges are **1-based, inclusive**; handles are integer ids
  (`0`/`nil` = current); failures `error()` (pcall-able); callbacks are plain Lua
  functions (both editors hold them alive — no manual registry).
- **Lua dialect:** write **Lua 5.1-compatible** source (Vim may link 5.1–5.4 /
  LuaJIT). No 5.2+/5.3+ syntax (`goto`, integer division, bitwise operators).
  Use the `liv.lua.compat` shim instead.
- **`require` must use string literals** (the bundler analyzes them statically).
  Declare dynamic deps / companion `.vim` / data files in a dependency manifest.
- **Backend selection happens once at import** (`init.lua` returns `_nvim` or
  `_vim`); never branch on `is_nvim` per call.
- **`liv.core` owns marshaling + the vimscript seam** (`call`/`eval`/`cmd`). `_vim`
  backends go through it; `_nvim` backends may call the Neovim native API directly
  (they only run on Neovim) but always via `core.marshaled` — never hand-roll
  marshaling.
- **On Neovim, prefer the native Lua API** (`vim.api.*`, `vim.uv`, `vim.json`, …)
  over a vimscript builtin for the same feature — add an `_nvim` backend when it
  differs observably (e.g. `vim.json` is compact, `vim.uv.fs_stat` is one call).

## TDD (Kent Beck) + test layers

- **L1 unit** (`spec/`, no editor, plain `lua`/`busted`): pure logic — marshaling
  `classify`, async runner, bundler analyze/rewrite/lockfile, `path`, etc.
- **L3 integration** (`test/`, real Vim `+lua` AND Neovim, headless): `liv.core`
  marshaling/bridge, each `_vim`/`_nvim` backend, end-to-end bundling. Both
  backends bind native refs (`core.marshaled(vim.fn.*)` / `vim.api.*`), so backend
  logic is asserted at L3 on both editors — there is no L2 mock-core layer.
- Write the failing test first; keep `liv.core` small so the L3 matrix stays small.

## Documentation layering

Code → How, Tests → What, Commits → Why, Comments → Why not.
Do not reference out-of-repo planning docs from in-repo artifacts; describe the
behavior/invariant directly.
