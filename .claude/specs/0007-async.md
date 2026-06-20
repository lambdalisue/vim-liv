# 0007 — async (`liv.lua.async` + editor-bound `liv.std`)

Provide "synchronous-looking asynchronous code" as one model across both editors.
The design splits cleanly along the namespace boundary ([0003](0003-architecture.md)):

- **`liv.lua.async` — the pure coroutine engine** (editor-independent, most of the
  code, L1-testable): `await`, `wrap`, `run`, and structured-concurrency
  combinators (`gather` / `select` / `channel` / `semaphore`). `schedule` and
  other leaves are **injected**, so it runs on any host and is unit-tested with
  fakes. Library authors depend on this directly to stay editor-independent.
- **Editor-bound `liv.std` modules** wire the real editor leaves into the engine
  and are **named by purpose** (e.g. `liv.std.process` for external processes).
  They supply a `schedule` (`vim.schedule` / `timer_start`) and leaves
  (sleep/system) so plugin authors get a ready-to-use API without injecting
  anything. They are **not** a same-named `liv.std.async` re-export.

```
combinators: gather / select / channel / semaphore  (liv.lua.async — pure)
runner + await + wrap                            (liv.lua.async — pure)
        |  schedule + leaves injected by an editor-bound liv.std module
        v
schedule (resume on main loop)        leaf: sleep / system / channel
  Neovim: vim.schedule                  Neovim: vim.uv / vim.system (libuv)
  Vim:    timer_start(0, fn)            Vim:    job_start / timer_start (vim.fn, marshaled)
```

Callbacks are passed as plain Lua functions (no `register`; see [0004](0004-core.md));
cancellation uses the domain id (timer/job).

## `liv.std.task` — the editor-bound runner

`liv.std.task` is the editor-bound facade: it selects the leaf backend once at
import and wires `schedule`/`timer`/`wait` into `liv.lua.async`, re-exporting the
pure `await`/`wrap`. (Re-exporting the *pure* helpers on an honestly editor-bound
module is fine — it does not hide editor-dependence.)

- `task.run(afn[, on_done])` → a handle `{ done, ok, result, cancel }`; runs `afn`
  with the editor `schedule` injected.
- `task.await` / `task.wrap` — the pure engine helpers.
- `task.sleep(ms)` — inside an async function, suspend ~`ms` then resume (one-shot
  timer leaf: `vim.uv` on Neovim, `timer_start` on Vim).
- `task.schedule(fn)` — run `fn` on the editor's main loop.
- `task.block(handle[, timeout])` — **synchronously pump the editor loop** until
  the task finishes, returning `(ok, result)`. This is a **drive-to-completion**
  helper for scripts / CI / `:Liv*` commands that must finish before returning —
  **not** for interactive use, where the editor already pumps the loop and
  blocking would freeze the UI. `handle.done` stays false on timeout (it returns
  rather than hangs). Pump: `vim.wait` on Neovim, a `:sleep` loop on Vim (which
  processes timers even in headless `-es`).

Verified on both editors that a chained zero-delay `timer_start(0, fn)` (the Vim
resume path) fires under the `:sleep` pump, so suspend/resume works in headless.

## Runner + await (pure Lua)

An async function runs inside a coroutine and calls `await(task)`, where
`task = function(resume)` calls `resume(ok, ...)` on completion. `run` takes its
`schedule` (and `on_done`) via an injected `opts` table — no editor dependency.

```lua
-- await: yield a CPS task; resume returns (ok, ...). Errors propagate as Lua errors.
function M.await(task)
  local res = pack(coroutine.yield(task))
  if not res[1] then error(res[2], 0) end
  return unpack(res, 2, res.n)
end

-- run an async fn to completion. opts.schedule (required), opts.on_done (optional,
-- called once as on_done(ok, result|err)). Returns a handle with :cancel().
function M.run(afn, opts)
  local schedule, on_done = opts.schedule, opts.on_done
  local co = coroutine.create(afn)
  -- `settled` guards the single terminal transition: once the run finishes,
  -- fails, or is cancelled, no further on_done / canceler may fire.
  local settled, cancel_current = false, nil
  local function finish(ok, value)
    if settled then return end
    settled = true
    if on_done then on_done(ok, value) end
  end
  local function step(...)
    if settled then return end
    local ok, task = coroutine.resume(co, ...)
    if not ok then return finish(false, task) end
    if coroutine.status(co) == "dead" then return finish(true, task) end
    local resumed = false
    cancel_current = task(function(...)
      if resumed or settled then return end
      resumed = true
      local a = pack(...)
      schedule(function() step(unpack(a, 1, a.n)) end)  -- resume on main loop
    end)
  end
  schedule(function() step() end)
  return { cancel = function()
    if settled then return end
    if type(cancel_current) == "function" then pcall(cancel_current) end
    finish(false, "cancelled")
  end }
end
```

- Errors propagate as Lua errors inside the coroutine (`pcall`/cleanup/rethrow
  work as in synchronous code).
- Resume always goes through `schedule` (main loop), because Neovim `vim.uv`
  callbacks run in a fast-event context with API restrictions. Costs one tick;
  buys safety and uniformity.
- A `task` may return a canceler; `:cancel()` invokes it. The single `settled`
  flag guards all three terminal sites (success, failure, cancel), so `on_done`
  fires exactly once even if `cancel()` is called after completion.

## wrap

```lua
-- wrap f(args..., cb) (cb called as cb(result...)) into an async fn awaitable via await().
function M.wrap(f)
  return function(...)
    local args = pack(...)
    return M.await(function(resume)
      args[args.n + 1] = function(...) resume(true, ...) end
      args.n = args.n + 1
      return f(unpack(args, 1, args.n))   -- may return a canceler
    end)
  end
end
```

## First-class Task (no Promise)

liv does **not** include a Promise (`then`/`catch`). Lua has coroutines, so
`await` gives sequential composition directly (JS needs Promise only because it
lacks coroutines). Adding a Promise would split "awaitable" into two kinds
(CPS task vs Promise) and duplicate the concurrency model, so it is **rejected**.

- The handle returned by `run` is a **first-class Task** (awaitable, `:cancel()`),
  which covers the one thing a Promise uniquely offered — a handle to an in-flight
  value.
- Structured concurrency is provided as combinators over Tasks: `gather`
  (await-all), `select` (first-to-finish), plus the coordination primitives
  `channel` and `semaphore` (see below). liv uses its own vocabulary — there is
  no `Promise`/`then`/`all`/`race`.
- No external-Promise interop is needed (there is no JS in this environment).

## Structured-concurrency combinators (pure Lua)

These live in `liv.lua.async` (pure, editor-independent). `gather`/`select`
spawn one child `run` per task onto the **parent's `schedule`**, inherited via
the engine's per-coroutine schedule registry (`runner.current_schedule()`), so a
combinator called from inside an async function needs no injected `schedule` and
children interleave through the one main loop. `channel`/`semaphore` need no
schedule: they park a `resume` in a FIFO waiter list and wake it later (the
parked `resume` already carries its own run's schedule from its `await`). The
engine stays minimal — the registry is one weak-keyed map plus one accessor.

- `gather(tasks)` → `results` — run an array of zero-arg async functions
  concurrently and return their results **in input order**, after **all**
  complete. **Fail-fast**: on the first task error, the rest are **cancelled**
  and that error propagates through `await`. An empty list resolves to `{}`.
- `select(tasks)` → `index, result` — run them concurrently and return the
  **1-based index** and result of the **first to settle**; the others are
  cancelled. "Settle" includes failure: if the first finisher errored, that
  error propagates through `await` (consistent with `await`). Requires ≥1 task.
- **Parent-cancellation propagates.** Both `gather` and `select` return a canceler
  from their `await` (stored as the await's `cancel_current`), so cancelling the
  PARENT run tears down **every** child run — not just the ones a fail-fast / first-
  settle path already cancels. A parent cancelled mid-flight never orphans children
  that would otherwise keep resuming on the shared schedule.
- `channel()` → `{ send, recv, close }` — an async **MPSC** channel. `send(value)`
  enqueues and **never blocks**; `recv()` awaits the next value, **parking** the
  caller (FIFO) until one is available; `close()` marks it closed. A `recv` that
  has drained the buffer returns the **`async.closed`** sentinel instead of
  parking (and parked recvs are woken with it on close). Values are stored packed,
  so **`nil` is a first-class queued value**, distinct from the closed sentinel —
  `recv` never returns a bare `nil` to signal closure. `send` after `close`
  errors.
- `semaphore(n)` → `{ acquire, release }` — a counting semaphore with `n`
  permits. `acquire()` awaits until a permit is free then takes one; `release()`
  returns a permit. **FIFO fairness**: `release` hands the freed permit directly
  to the longest-waiting acquirer rather than incrementing and racing. Combined
  with `gather` it **bounds concurrency** (e.g. `permits = 2` over 4 gathered
  tasks keeps at most 2 running at once).

## Leaf backends (wired by editor-bound `liv.std`)

These are editor-dependent and therefore supplied by `liv.std` modules, injected
into the pure engine above.

| leaf | Neovim | Vim (default Lua) |
| --- | --- | --- |
| `schedule(fn)` | `vim.schedule` | `timer_start(0, fn)` |
| `sleep(ms)` | `vim.uv` timer | `timer_start(ms, fn)` / cancel `timer_stop` |
| `system(cmd)` | `vim.system(...,cb)` / `:kill()` | `job_start` + `exit_cb`/`out_cb` / cancel `job_stop` |
| channel | `vim.uv` | `ch_open`/`ch_*` |
| fs | `vim.uv.fs_*` (true async) | sync by default (see below) |

## Honest constraint: Vim has no libuv

`fs` is **synchronous by default** on Vim (`readfile`/`writefile`; awaitable but
internally blocking, binary-safe). True async fs on Vim requires offloading to an
external process, which is not worth it (portability cost defeats "works with just
`+lua`"). True async is **opt-in** (`fs.read(path,{async=true})`, reusing the
process leaf), gated by `liv.std.has("fs.async")`. Neovim is true-async for free.
