# 0010 — Testing

SPEC + TDD (Kent Beck): write the failing test first, make it pass, refactor.
The specs in this directory are the contract; tests encode them.

## Runner: `liv.tester` (one command, no per-project boilerplate)

Tests use **`liv.tester`**, liv's own dependency-free, cross-editor framework
(busted-shaped `describe`/`it` + luassert-shaped `assert`); no existing Lua
framework spans both Vim `+lua` and Neovim (vusted/plenary are Neovim-only). One
entry runs everything — `bin/liv-tester` (or `:LivTest`): it runs `spec/` as L1
in-process and `test/` as L3 inside both editors, then aggregates. Authors get
the same tool for their own liv plugins. Dev-only, never vendored.

## Layers

- **L1 unit** — `spec/`, no editor, run in-process. Pure logic:
  marshaling `classify` ([0005](0005-marshaling.md)), async `runner`
  ([0007](0007-async.md)), bundler `analyze`/`rewrite`/`lockfile`/`migrate`
  ([0008](0008-bundler.md)), `liv.lua.compat`, `liv.lua.path`. The whole
  `liv.lua` namespace is editor-independent, so all of it is L1. Fast; run anywhere.
- **L3 integration** — `test/`, real **Vim `+lua` AND Neovim**, headless. Both
  `_vim` and `_nvim` backends bind native function references
  (`core.marshaled(vim.fn.*)` / `core.marshaled(vim.api.*)`), so neither runs
  without a real editor: backend contract logic (index math, call sequence,
  `set_lines` edge cases) is asserted here on both editors, not against a mock
  core. Also covers `liv.core` marshaling/bridge (round-trip, userdata→table) and
  end-to-end bundling (vendor a fixture plugin and run it on both). Keep
  `liv.core` small so this matrix stays small.
- (There is no L2 mock-core layer: since both backends bind native refs, the old
  call-sequence-against-a-mock approach was retired with the `vim.fn` unification.
  Backends are still `function(core)` factories — that injection point remains —
  but std backends are exercised at L3.)

## Dependency injection (enables L1)

- `liv.std` modules obtain `liv.core` via the factory injection point.
- The async runner obtains `schedule` and leaf primitives so tests can drive
  coroutines synchronously with fakes.
- No global state: never mutate global `vim`; no hidden singletons.

## Bundler tests

- Pure tool → **golden-file** tests (input tree → expected vendored output +
  lockfile). Migration-notice selection tested with fixture `MIGRATIONS.md`.

## Dev vs release

- Develop modular (each module independently testable).
- Release/bundle exercises the integration path (the exact thing that ships).

## First TDD targets

1. `liv.core` value `classify` + normalize (L1), then round-trip on real editors (L3).
2. `liv.bundler` `analyze` (static `require` transitive closure) (L1).
3. `liv.lua.async` `runner`/`await`/`wrap` with fakes (L1).
