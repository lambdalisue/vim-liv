# Rule: SPEC + TDD

Follow Kent Beck's TDD: write a failing test first, make it pass, refactor.
The spec under `docs/specs/` is the contract; tests encode it.

## Test layers

- **L1 unit** — `spec/`, no editor. Plain `lua` / `busted`. For pure logic:
  marshaling `classify`, async `runner`, bundler `analyze`/`rewrite`/`lockfile`,
  the whole `liv.lua.*` namespace (`compat`, `async`, `path`), etc. Fast; run anywhere.
- **L3 integration** — `test/`, real **Vim `+lua` AND Neovim** (headless). For
  `liv.core` marshaling/bridge, each `_vim`/`_nvim` backend, and end-to-end
  bundling. Both backends bind native refs (`core.marshaled(vim.fn.*)` /
  `core.marshaled(vim.api.*)`), so neither runs without an editor — backend
  contract logic (call sequence, index math, edge cases) is asserted here, not
  against a mock core. Keep `liv.core` tiny so this matrix stays small.
  (No L2 mock-core layer: the `vim.fn` unification retired it.)

## Dependency injection (to keep things testable)

- `liv.std` modules receive `liv.core` such that tests can substitute a mock.
- The async runner receives `schedule` / leaf primitives so tests drive
  coroutines synchronously with fakes.
- Avoid global state (no global `vim` mutation; no hidden singletons).

## Documentation layering

Code → How, Tests → What, Commits → Why, Comments → Why not.
