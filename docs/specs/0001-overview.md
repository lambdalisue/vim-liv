# 0001 — Overview

## Goal

Build a framework for writing **Lua** plugins that run on **both Vim 9 (`+lua`)
and Neovim**, such that **installing only the consumer plugin** is enough: all
dependencies are bundled into it.

- End users install only the target plugin (no `liv`, no Deno, nothing extra).
  All dependencies are vendored into the plugin (vital.vim's embedding philosophy,
  applied to Lua).
- Plugin authors write **a single Lua source** that runs on both editors.
- Compatibility and safety are carried by **bundled Lua** (and, exceptionally,
  Vim 9 script companions).

## Components

One monorepo (`vim-liv`, itself a Vim/Neovim plugin) hosting six namespaces —
three runtime (vendored) and three dev tools (never vendored):

- `liv.core` — minimal invariant seam over the editor + value marshaling.
- `liv.std` — liv's own **editor-dependent** cross-editor API surface.
- `liv.lua` — **editor-independent** pure-Lua modules (compat / async / path / …).
- `liv.bundler` — build-time bundler (dev tool).
- `liv.tester` — cross-editor test framework + runner (dev tool).
- `liv.generator` — build-time codegen of typed editor-API wrappers from pinned
  Vim/Neovim docs (dev tool).

See [0003-architecture](0003-architecture.md).

## Scope / hard constraints

- **Vim side targets only `+lua`-enabled Vim 9.** A Vim without `+lua` cannot be
  rescued by bundled Lua.
- **The Lua version Vim links is not controllable** (5.1–5.4 or LuaJIT). Neovim
  is always LuaJIT (5.1-compatible). The constrained side is Vim; design for Vim,
  and Neovim is satisfied naturally.
- **Native (C) modules are out of scope** for bundling (not portable; defeats the
  zero-extra-install goal). Pure Lua only.
- **Capabilities Vim lacks** (treesitter, lsp, true libuv) are impossible to make
  cross-editor by *any* approach. liv keeps them out of the contract and exposes
  `liv.has()` + graceful degradation (see [0002](0002-principles.md),
  [0006](0006-std.md)).

## Non-goals

- Running arbitrary existing Neovim plugins unchanged on Vim.
- Mirroring Neovim's full `vim.*` API (see [0002](0002-principles.md) §
  "own the contract").
