# Rule: namespace boundaries

Six namespaces in one monorepo. Respect their boundaries. Three are runtime
(`liv.core`/`liv.std`/`liv.lua`, vendored); three are dev tools (`liv.bundler`/
`liv.tester`/`liv.generator`, never vendored).

Placement rule: **needs the editor to function → `liv.std`; pure computation →
`liv.lua`; raw editor primitive → `liv.core` (rare)**. Never flatten `liv.std`
and `liv.lua` behind a single re-export — the namespace must keep advertising
whether a module is editor-dependent (can degrade) or pure (guaranteed).

## `liv.core` (seam — vendored, editor-dependent)

- Owns **marshaling** and the **vimscript** seam. The only module that calls
  `vim.call`/`vim.eval`/`vim.command` and the only place that marshals.
- Public primitives: `call` (vimscript by name), `marshaled` (wrap a Lua callable
  reference with marshaling — used by `_nvim` backends to bind native APIs),
  `eval`, `cmd` (+ maybe `batch`), `is_nvim`, marshaling API (`NIL`, `list`,
  `dict`, `empty_dict`, `is_list`, `is_dict`, `to_editor`, `from_editor`), and the
  require bootstrap searcher.
- Performs **bidirectional value marshaling** inside these primitives, so both
  editors return the same plain Lua values. Keep it minimal and invariant; do
  not add per-function or feature APIs here.

## `liv.std` (editor-DEPENDENT API — vendored)

- liv's own cross-editor API; holds **only editor-dependent modules**.
- Each module is `area/init.lua` selecting a backend (`_nvim` / `_vim`) ONCE at
  import (a factory `function(core) return {...} end`). Both backends bind native
  functions as **marshaled references** — `_vim` via `core.marshaled(vim.fn.X)`,
  `_nvim` via `core.marshaled(vim.api.X)` — so they share one shape and marshaling
  stays in core, never hand-rolled. `core.eval`/`cmd` handle expressions/Ex
  commands; `core.call` (by name) is kept for dynamic dispatch (the Vim 9 callback
  registry). `.vim` companions only as a hot-path optimization.
- **On Neovim, prefer the native Lua API** (`vim.api.*`, `vim.uv`, `vim.json`, …)
  over routing the same feature through a vimscript builtin. It is the correct,
  often more capable, and more consistent path — e.g. `vim.json.encode` is compact
  while `vim.fn.json_encode` emits spaces, and `vim.uv.fs_stat` is one native call
  vs three vimscript ones. A module whose `_vim` and `_nvim` bindings would behave
  identically can share one path, but gets a distinct `_nvim` backend when the
  native API differs observably (output shape, types, capability).
- Modules are **named by purpose** (e.g. `liv.std.process`), not by the pure
  engine they use. An editor-dependent module may wire editor leaves into a pure
  `liv.lua` engine rather than reimplement it.

## `liv.lua` (editor-INDEPENDENT pure Lua — vendored)

- Pure-Lua modules that never touch the editor (not even `liv.core`); they depend
  only on other `liv.lua` modules. Deterministic on every host, L1-testable,
  safe for a library to depend on with no backend matrix.
- Members: `liv.lua.compat` (Axis A shim), `liv.lua.async` (pure coroutine
  engine; `schedule` injected), `liv.lua.path` (posix/unc flavours), etc.

## `liv.tester` (dev tool — NEVER vendored, editor-independent)

- A dependency-free, cross-editor test framework + runner (busted-shaped
  `describe`/`it`, luassert-shaped `assert`). Pure Lua, so one suite runs both
  in-process (L1) and inside Vim/Neovim (L3). Canonical entry `liv.tester.cli`;
  `bin/liv-tester` and (planned) `:LivTest` are thin shims.
- Plugin authors use it to test their own liv plugins. Not in any consumer
  runtime require graph → never vendored.

## `liv.bundler` (dev tool — NEVER vendored, editor-independent)

- Pure Lua build-time tool: analyze (static `require`), rewrite (namespace),
  lockfile, migrate (notices), source resolvers (`rtp`/`git`/`luarock`/`path`),
  vendor (clean + binary-safe copy).
- MUST NOT be reachable from a consumer plugin's runtime `require` graph (the
  bundle's static analysis would otherwise pull it in). It is invoked only by the
  `:Liv*` commands / standalone CLI.
- May read `&runtimepath` for the `rtp` source resolver; otherwise no editor deps.

## `liv.generator` (dev tool — NEVER vendored, editor-independent)

- Pure Lua build-time code generator: parses **pinned** Vim/Neovim documentation
  (`options.txt` / `builtin.txt`) to emit typed metadata + LuaLS annotations for
  the editor-API wrappers (`liv.std.function` builtins, `liv.std.option` options), so
  authors get completion / type-checks pinned to a known editor version
  (denops-style). Pinned versions live in `liv.generator.supported_versions`.
- Emits source that is committed to the repo; it runs only at dev time
  (`bin/liv-generator`), never in a consumer's runtime require graph → never
  vendored. No editor dependency — it reads doc text files, not a live editor.

## Bundler distribution

- `plugin/liv.vim` is a thin command shell delegating to `liv.bundler`.
- Default source is `rtp` (resolve from runtimepath); deps and versions are
  recorded per-module in the lockfile.
