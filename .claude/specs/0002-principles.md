# 0002 — Principles

These are the top-level decisions that everything else follows.

## P1. Own the contract (do NOT polyfill Neovim's API)

liv owns its own stable, cross-editor API contract (like `@denops/std`).

Rejected alternative — "make Neovim's API the contract":

- **Upstream treadmill**: chasing an API you do not control, forever behind.
- **Silent gaps**: promising "all of Neovim" lets authors unknowingly use
  Vim-impossible APIs that then break silently on Vim.

Owning the contract instead means:

- The contract contains **only operations feasible on both editors** → whatever
  is in the contract is **guaranteed to work on both** (this is the product's
  core promise: "install only the plugin, works on both").
- liv versions its own evolution (not bound to upstream).
- Power features (treesitter, lsp, …) are out of contract; authors branch
  intentionally via `liv.has()` with graceful degradation — never silent failure.

## P2. Distinct naming (no "similar but different")

- **Never mimic Neovim API names/shapes** (`nvim_*`, `vim.api`, `extmark`,
  `vim.uv`, `vim.schedule`). False familiarity causes silent bugs. Different
  behavior → different name.
- Domain vocabulary (buffer/window/tabpage/option) is fine.
- Conventions (loud, uniform): ranges **1-based inclusive**; integer handles
  (`0`/`nil` = current); positions `{line, col}` 1-based; errors via `error()`;
  callbacks are plain Lua functions.

## P3. Testability is structural

- Single editor **seam** (`liv.core`) centralizes marshaling; pure logic is
  pulled out of the editor edges so it is unit-testable with no editor at all.
- Pure logic is separated from editor edges (marshaling `classify`, async runner,
  version resolver are pure functions — all L1). Editor-bound backends bind native
  refs through `core.marshaled`, so they are verified in real editors at L3.
- Two test layers: L1 (pure, in-process) and L3 (real Vim + Neovim); see
  [0010](0010-testing.md).

## P4. Distribution: bundler vendor; never mutate global `vim`

- liv is multi-file; the **bundler** vendors it into the consumer plugin with
  namespace rewriting (this is the mechanism that makes "install only the plugin"
  true). The bundler is therefore a **core component**, not optional.
- **Do NOT monkeypatch the global `vim` table** (order-dependent, hard to isolate,
  a version-skew hazard, and bad for testability). Authors alias explicitly:
  `local liv = require('myplugin.vendor.liv')`.

## P5. Co-versioned monorepo (ships-what-tested)

`liv.core` / `liv.std` / `liv.bundler` live in one repo, co-versioned, and the
exact combination that gets bundled is verified together in CI (Vim + Neovim).
This makes "the bundled output definitely works" easy to guarantee — the same
reason vital.vim co-locates its modules and vitalizer.
