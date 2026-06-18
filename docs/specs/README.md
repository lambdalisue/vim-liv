# liv specifications

Normative specifications for **liv**. These are the source of truth; code and
tests implement them.

| # | Spec | Summary |
| --- | --- | --- |
| 0001 | [Overview](0001-overview.md) | Goal, scope, hard constraints |
| 0002 | [Principles](0002-principles.md) | Own-the-contract, distinct naming, testability, no global `vim` |
| 0003 | [Architecture](0003-architecture.md) | Monorepo, six namespaces (core/std/lua + bundler/tester/generator tools), placement rule, compatibility axes |
| 0004 | [Core](0004-core.md) | `liv.core` seam: primitives, callbacks, bootstrap |
| 0005 | [Marshaling](0005-marshaling.md) | Bidirectional value marshaling; empty-table API |
| 0006 | [Std](0006-std.md) | `liv.std` editor-dependent API catalog, conventions, capability/degradation |
| 0007 | [Async](0007-async.md) | `liv.lua.async` pure engine + editor-bound `liv.std`: runner, await, wrap, leaf, first-class Task (no Promise) |
| 0008 | [Bundler](0008-bundler.md) | `liv.bundler`: vitalizer essence, rewrite, lockfile, migration |
| 0009 | [Commands & CLI](0009-commands.md) | CLI-primary (`liv.<tool>.cli`); `bin/` + `:Liv*` thin shims; bundler, tester & generator commands, `--source` |
| 0010 | [Testing](0010-testing.md) | `liv.tester` runner (`bin/liv-tester`), L1/L3 layers, TDD, dependency injection |

## Conventions used in these specs

- **MUST / SHOULD / MAY** carry their usual normative meaning.
- Code examples are illustrative unless marked normative.
- "Vim" means Vim 9 built with `+lua`; "Neovim" means Neovim with its built-in
  LuaJIT. "Both editors" means both of these.
