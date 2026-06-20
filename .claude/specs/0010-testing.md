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

## Registry, three states, and tags

`describe`/`it` accept an optional opts table between the name and the body:
`describe(name, { tags = {…} }, fn)` and `it(name, { tags = {…} }, fn)`. The two-
argument forms `describe(name, fn)` / `it(name, fn)` stay valid (the second
argument being a function selects the no-opts overload). A group's tags compose
onto every nested test (group tags ∪ test tags).

Every test ends in one of **three states**: `passed`, `failed`, or `skipped`.
`run()` returns `passed, failed, skipped, failures`. A test is skipped when it is
`it.skip` / `describe.skip` (registered but not run), or when its body calls
`pending(reason)` (the body is abandoned as skipped, not failed). Focus is the
mirror: if any `it.only` / `describe.only` exists anywhere, only the focused
subtrees are candidates to run.

Registries are **instances** — `tester.new()` returns a fresh
`describe`/`it`/`before_each`/`after_each`/`before_all`/`after_all`/`finally`/
`pending`/`async`/`run`/`reset` surface closing over its own tree, so a test of
the framework never perturbs the live run. The module-level names are a default
instance.

## Hooks

Four hook scopes compose around a test body:

- `before_each` / `after_each` — run around **every** candidate test in the
  group's subtree (ancestor hooks compose: outer `before_each` first, inner last;
  `after_each` the mirror). An `after_each` always runs even when the body failed.
- `before_all` / `after_all` — describe-scoped, run **once** per group. They are
  **lazy**: a group's `before_all` fires just before the FIRST candidate body in
  its subtree actually runs (so it precedes that test's `before_each`), and its
  `after_all` fires once the subtree finishes (after the last `after_each`) — but
  **only if its `before_all` fired**. A group whose tests are all skipped,
  filtered out, or unfocused therefore runs neither hook (no setup leaks into a
  subtree that never executes). Nesting runs `before_all` outermost-first and
  `after_all` innermost-first.
- `finally(fn)` — registered from **inside a test body**, guaranteed per-test
  cleanup. Finallys run immediately after the body — **before** `after_each` — in
  **reverse** registration order, whether the body passed, failed, or called
  `pending()`. A `finally` that itself errors turns an otherwise-passing or pending
  test into a **failure**.

## Selection

Tests are filtered by a **selector mini-language** (`liv.tester._select`), pure
Lua so L1 and L3 filter identically. A selector is a comma-separated list of
terms, ANDed; each term is `name:<pat>` (matches the composed full title),
`tag:<pat>` (matches any composed tag), or a bare word (= `name:`); a leading `!`
negates. Patterns are Lua patterns, case-insensitive. Multiple selectors are
ORed. An empty selection matches everything.

A test is counted only when it is a **candidate** — it passes the focus gate and
the selector. Non-candidates do not run and are not counted; only
`skip`/`pending` count as skipped.

## CLI

`bin/liv-tester` forwards argv to `liv.tester.cli`, parsed with `liv.lua.argument`:

- positional `PATH…` restrict the run to spec/test files whose path ends with the
  given suffix;
- `--select=<selector>` filters tests (repeatable; multiple selectors OR). It is
  propagated to L3 children via the `LIV_SELECT` env var (newline-joined);
- `--reporter=<name>` selects the L1 output reporter (`spec`, `tap`, `jsonl`,
  `junit`); default `spec` on a terminal, `tap` otherwise. An unknown name is a
  usage error (exit 2);
- `--verbose` / `--quiet` adjust the `spec` reporter's detail;
- `--seed=<N>` randomizes test order reproducibly (see Workflow);
- `--failed` reruns only the previous run's failures (see Workflow);
- `--list` prints the filtered candidate names without running;
- `--watch` re-runs on file changes (see Workflow);
- `--jobs=<N>` / `--fail-fast` / `--max-failures=<N>` / `--editor=<which>` govern
  L3 orchestration (see L3 process isolation);
- `--help`, `--version`.

The first positional may be the `init` **subcommand** (scaffold a config + example
spec, see Workflow); it is dispatched before path handling so `init` is never
treated as a path.

Values are supplied with `=` (`--select=tag:smoke`): per liv's argument grammar a
`=`-less flag is a boolean and never consumes the next token.

### Exit codes

`bin/liv-tester` returns a **structured exit code**: `0` all passed, `1` test
failures, `2` usage error (e.g. an unknown `--reporter`), `4` no tests found.

## Reporters (run() event interface)

`run(reporter, opts)` drives a reporter through an **event interface** — a table
of optional callbacks, called as the registry tree is walked:

- `on_run_start(ctx)` — once, before any test;
- `on_suite_enter(name)` / `on_suite_leave(name)` — around each **named** group
  (the unnamed root is skipped);
- `on_test_start(name)` — before a candidate runs;
- `on_test_end(report)` — after it resolves, where `report` is
  `{ name, status, duration, error?, file?, line? }` (`status` is one of the three
  states; `duration` is seconds via `os.clock`; `file`/`line` are the `it()`
  declaration site captured with `debug.getinfo`);
- `on_run_end(stats)` — once, `stats = { passed, failed, skipped, duration }`.

A bare **function** is still accepted as the first argument: it is treated as the
legacy `on_progress(status)`, invoked per resolved candidate. `run()` keeps
returning `passed, failed, skipped, failures` regardless, so existing callers
(`_editor.lua`, L1) are unaffected.

Reporters (`liv.tester.reporters`) are **pure factories** `fun(opts) -> callbacks`
that consume this interface; `opts` injects the output sink (`write`) and the
resolved environment booleans (`color`, `verbose`, `quiet`, `slow_threshold`), so
they are deterministic and L1-testable (feed a canned event stream + a capturing
writer, assert the bytes). Environment detection (TTY → default reporter + color)
lives in the CLI, never in a reporter. Shipped reporters:

- **spec** — human: indented suite headings, `✓`/`✗`/`⊘` + per-test ms, a `SLOW`
  marker past a threshold, optional ANSI color;
- **tap** — CI lingua franca: a `1..N` plan, `ok`/`not ok N`, pending →
  `ok N # SKIP`, failure detail as `# …` diagnostics;
- **jsonl** — newline-delimited JSON, one `test` object per result + a final
  `summary` (a tiny self-contained encoder; the tester cannot use editor-dependent
  `liv.json`);
- **junit** — a single `<testsuite>` with one `<testcase>` per test (`<failure>` /
  `<skipped>` children).

The cross-layer roll-up (`L1`/`L3` summary lines + `TOTAL`) is the CLI's own
aggregation and is always printed; the reporter renders the L1 per-test detail
above it.

`assert.same` failures name the **first diverging key path** (with the two leaf
values) before dumping the full tables, so the reader sees exactly what differs.

## Assertions (luassert-shaped)

`tester.assert` is callable (asserts truthiness) and carries matcher methods that
`error()` (pcall-able) on failure with an **expected/got** message. Beyond the
core set (`equal`/`same`/`is_*`/`has_error`):

- `match(value, pattern)` — `value` matches a **Lua pattern**;
- `length_of(value, n)` — a string/sequence has `#`-length `n`;
- `includes(value, needle)` / `contains` (alias) — a substring of a string, or a
  deep-equal element of a sequence;
- `truthy(v)` / `falsy(v)` — neither `nil` nor `false` / `nil` or `false`,
  **distinct** from the strict `is_true`/`is_false`;
- `has_no_error(fn)` — `fn` does not error (returns its result);
- `has_error(fn, expected)` — `fn` errors, message contains the **plain
  substring** `expected`; `has_error_matching(fn, pattern)` is the **Lua pattern**
  variant. Both return the raised error.

## Async test helper

Liv ships an async runner, so the tester drives an async function to completion
**synchronously** instead of every spec hand-rolling a queue+drain loop:

- `tester.async(afn)` runs `afn` (a `liv.lua.async` async function) over the pure
  runner with a drainable fake `schedule`, then returns its value or **re-raises**
  its error (or an awaited failure). If the schedule drains without the run
  settling — the body parked on a task that never resumes — it raises
  `async did not complete` rather than hanging.
- `it.async(name, [opts,] afn)` is a normal `it` whose body is driven through
  `tester.async`, so an async leaf failure surfaces as an ordinary failed test.

(`liv.tester._async` lazy-requires the runner, so loading `liv.tester` never
pulls the async machinery.)

## Testing non-exported internals

A module's local (file-scoped) functions are not reachable from a test. The
sanctioned convention, rather than porting vim-themis's `scriptnames` hack, is an
explicit **test-only export**: expose the internals under a clearly-marked field
so the public surface stays intentional.

- Add a `M._internal` (or `M.__test`) table holding the locals a test needs:
  `M._internal = { normalize = normalize, parse = parse }`. The leading underscore
  / `__test` name advertises "not part of the contract — for tests only", so it is
  not mistaken for public API and never relied on by consumers.
- As an **escape hatch** when even that is undesirable (e.g. a closure upvalue with
  no natural export point), a test may reach a value with `debug.getupvalue` /
  `debug.getlocal`. Prefer the explicit export; reserve reflection for the cases an
  export cannot reach.

This keeps the public API owned and deliberate (see
[`naming-and-contract`](../rules/naming-and-contract.md)) while still letting pure
internals be unit-tested.

## L3 process isolation and robustness

L3 (`test/`) is liv's differentiator — the same source must hold on **both** Vim
`+lua` and Neovim — so its runner is the sturdiest part of the tester. Each
`test/` file runs in its **own editor invocation per editor** (one child per
file × editor cell), reusing the `_editor.lua` env + result-file protocol with a
one-entry list file per child. A crash or hang in one file therefore costs only
that cell, never the whole layer:

- a child that writes **no/partial result file** (it crashed) is counted as a
  **failure naming the file+editor** — never silently lost;
- a child that **hangs** is `SIGTERM`-killed at a per-file **timeout** and
  counted as a failure;
- results aggregate **deterministically** in file × editor order regardless of
  child completion order.

The CLI governs orchestration:

- `--jobs=<N>` runs up to N child editors in parallel (default 1, sequential).
  The **same file never runs on two editors at once** — a file's external side
  effects (e.g. a shared temp dir) are per-file global, so its cells serialize
  while different files run concurrently;
- `--fail-fast` stops launching new cells after the first failure;
  `--max-failures=<N>` after N failures. Un-launched cells are reported skipped;
- `--editor=<nvim|vim|both>` chooses which editor(s) run L3 (default both;
  skip-if-missing). The legacy `LIV_L3_EDITORS` env stays as a fallback when no
  `--editor` is given, with CLI taking precedence.

## Workflow

### Config file (`.liv-tester.lua`)

A project's defaults live in a **`.liv-tester.lua`** — a **Lua file that returns a
table**, NOT JSON (`liv-tester` runs under a bare interpreter where the editor-
dependent `liv.json` is unavailable, and a Lua file needs no parser). It is
**discovered by walking up** from the project root to the filesystem root; the
nearest one wins. Precedence is **CLI > config > default**, resolved per key — a
flag the user did not set never clobbers a config value (presence, not
truthiness, so an explicit `--fail-fast` differs from absence). A config that
fails to load (syntax/runtime error, or a non-table return) is a **usage error**
(exit 2). Recognized keys:

- `reporter` — default reporter name;
- `select` — default selectors (a list; multiple = OR);
- `timeout` — per-file L3 timeout (seconds);
- `jobs` — parallel L3 child editors;
- `max_failures` / `fail_fast` — the L3 failure budget;
- `editor` — `nvim` | `vim` | `both`;
- `includes` / `excludes` — file globs scoping the discovered spec/test files
  (only `*` is magic — one or more non-`/` characters; every other character is
  literal; excludes win over includes).

`liv-tester init` scaffolds a starter `.liv-tester.lua` (every key documented,
commented out so it behaves as default) plus an example `spec/example_spec.lua`.
It **refuses to overwrite** an existing config.

### `--failed` rerun

Each run writes its failures (full title + `file:line` origin, captured at `it()`
with `debug.getinfo`) to a **last-run state file** (`.liv/last-run.lua`, a Lua
file like the config). `--failed` restricts the next run to **exactly** those
tests. The match is **exact full-title set membership**, NOT the Lua-pattern
`--select` path — test names routinely contain pattern-magic characters
(`-`, `(`, `.`). `--failed` ANDs with any active `--select`. Cross-layer: L1
failures come from the structured `run()` records; L3 failures are parsed back
out of each child's `FAIL\t<name>` result lines (the parent sees only those), so
a `--failed` rerun reaches L3 tests too, propagated to children via `LIV_FAILED`
(newline-joined exact names). `.liv/` is git-ignored.

### Randomized order (`--seed=N`)

`--seed=N` shuffles **each registry node's direct children** (never a global
flatten — that would break `before_all` laziness and `before_each` composition),
surfacing inter-test coupling. The shuffle is a **self-contained LCG** seeded by
`N`, NOT `math.random` (whose algorithm differs across LuaJIT and PUC-Lua 5.1–5.4,
so the same seed would shuffle differently on Vim's Lua vs Neovim's LuaJIT). It is
deterministic on **every** host, so a failing order reproduces; the seed is
**echoed**. Randomization is **strictly opt-in** — a run with no seed stays in
declaration order, so the suite's own green gate is never flipped by latent
ordering. The seed crosses to L3 children via `LIV_SEED`.

### `--watch` and `--list`

- `--list` prints the (filtered) candidate test names without running any body —
  L1 names are enumerated in-process via `tester.list`; L3 files are listed by
  path (enumerating their names would need an editor spawn per file).
- `--watch` re-runs the suite on any change under `spec/` / `test/` / `lua/`, by
  **mtime polling** (pure Lua, no inotify/libuv). Best-effort: it runs once, then
  re-runs on change, until interrupted.

### `:LivTest`

`:LivTest [init] [PATH…] [options]` (registered by `plugin/liv.vim`) is a **thin
shim** over the same `liv.tester.cli.main` as `bin/liv-tester` — it resolves
vim-liv's root from `&runtimepath`, treats the working directory as the plugin
under test, and forwards its arguments as argv. `cli.main` **returns** the
structured exit code (it never calls `os.exit`, which would kill the editor); the
shim only reports it. As with all `:Liv*` commands it adds no logic of its own.

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
