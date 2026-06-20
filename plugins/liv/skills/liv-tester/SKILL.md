---
name: liv-tester
description: How to write and run cross-editor tests for a liv plugin with liv.tester — L1 (spec/, editor-free) vs L3 (test/, real Vim +lua AND Neovim, headless), describe/it/assert, selectors (name:/tag:, it.only/it.skip), reporters (spec/tap/jsonl/junit), and bin/liv-tester / :LivTest flags (--select, --failed, --seed, --watch, --jobs, --editor, --fail-fast/--max-failures). Use when writing test specs, running the suite, debugging failures, or filtering tests.
---

# Testing with liv.tester

`liv.tester` is a dependency-free, cross-editor test framework + runner. Because it
is pure Lua, one suite runs both **in-process** (L1) and **inside the editors**
(L3). It is a **dev tool: never vendored**. Canonical entry `liv.tester.cli.main`;
shims are `bin/liv-tester` and `:LivTest`.

## Two layers

- **L1 unit** — `spec/`, **no editor**, plain `lua`/`busted`. For pure logic
  (`liv.lua.*`, marshaling classify, async runner, bundler analyze/rewrite/lockfile,
  path, …). Fast; runs anywhere.
- **L3 integration** — `test/`, real **Vim `+lua` AND Neovim**, headless. For
  `liv.core` marshaling/bridge and each `_vim`/`_nvim` backend. Both backends bind
  native refs, so backend contract logic is asserted here on both editors — there
  is no L2 mock-core layer. Each `test/` file runs in its **own** editor process
  per editor, with a per-file timeout, so one crashing/hanging spec costs only that
  cell.

By convention many `test/` describe names carry a `(L3)` suffix; the framework now
labels the layer structurally, so it is redundant but left in place.

## Writing tests (busted-shaped)

```lua
local buffer = require("liv.std.buffer")

describe("liv.std.buffer (L3)", function()
  before_all(function() --[[ setup ]] end)
  after_all(function() --[[ teardown ]] end)

  it("set_lines replaces a 1-based inclusive range", function()
    buffer.set_lines(0, 1, 1, { "hello" })
    assert.same({ "hello" }, buffer.lines(0, 1, 1))
  end)

  it.skip("not ready yet", function() end)
end)
```

- `describe` / `it` / `before_all` / `after_all` / `finally`; `pending()` and
  `it.skip` mark skipped; `it.only` / `describe.only` focus.
- luassert-shaped `assert`: `same` (deep equal — names the first diverging key
  path on failure), `equal`, `truthy`, `match`, `length_of`, `includes`, … and an
  async helper that drives a `liv.lua.async` function to completion synchronously.
- **Dependency injection:** `liv.std` modules receive `liv.core` (substitute a mock
  in L1); the async runner receives `schedule`/leaf primitives so tests drive
  coroutines synchronously. Avoid global state (no global `vim` mutation, no hidden
  singletons).

## Running

```sh
bin/liv-tester                 # spec/ as L1 + test/ as L3 (both editors)
bin/liv-tester --editor=nvim   # L3 on Neovim only
bin/liv-tester init            # scaffold .liv-tester.lua + an example spec
```

Flags (values use `=`, e.g. `--select=tag:smoke`):

- `--select=<selector>` — filter by a `name:`/`tag:` mini-language (`!` negation,
  comma = AND, repeat the flag = OR). Repeatable; ANDs with `--failed`.
- `--reporter=<name>` — `spec` (human; default on a TTY), `tap` (default
  non-TTY), `jsonl`, or `junit`.
- `--verbose` / `--quiet` — more / less spec-reporter detail.
- `--jobs=<N>` — run up to N L3 child editors in parallel (default 1).
- `--fail-fast` / `--max-failures=<N>` — stop launching new L3 cells after the
  first / Nth failure.
- `--editor=<which>` — `nvim`, `vim`, or `both` (default).
- `--seed=<N>` — randomize order reproducibly (echoes the seed; opt-in, default is
  declaration order).
- `--failed` — rerun ONLY the previous run's failures (exact full-title match —
  test names contain pattern-magic chars, so it is NOT the `--select` pattern path).
- `--list` — print the filtered candidate names without running.
- `--watch` — re-run on any change under `spec/` `test/` `lua/` (mtime poll).

**Exit codes:** `0` all passed, `1` test failures, `2` usage error, `4` no tests
found.

**Config:** `.liv-tester.lua` at the project root; precedence is **CLI > config >
default** (an absent flag never clobbers a config value).

## Cross-layer output

One reporter renders **every** layer (L1, then each L3 editor) as one continuous,
sectioned stream: a per-layer header (`# L1 (no editor)` / `# L3 (nvim)` / …),
**continuous numbering** across layers, then the plan and a single summary, with
the L1/L3 roll-up + `TOTAL` below. Each L3 test is visible individually (not just
an aggregate count); a crash/timeout/skip-budget cell is synthesized into a visible
record so the plan count always matches the summary. Reporters render the layer
their own way (spec a bold header, tap a `# <layer>` comment, jsonl a `layer`
field, junit a `<testsuite>` per layer inside a `<testsuites>` root).

## Deeper reference

vim-liv repo spec: `.claude/specs/0010-testing.md`. Related skills:
`liv-plugin-authoring`, `liv-library-api`.
