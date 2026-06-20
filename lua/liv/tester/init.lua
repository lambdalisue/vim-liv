-- liv.tester — a small, dependency-free, cross-editor test framework.
--
-- liv's reason to exist is running one Lua source on both Vim (+lua) and Neovim;
-- testing has the same need, and no existing Lua framework spans both editors
-- (vusted/plenary are Neovim-only; vim-themis is Vim-script). So liv ships its
-- own: a busted-shaped registry + luassert-shaped `assert`, pure Lua, so the
-- same suite runs under a standalone interpreter (L1) and inside either editor
-- (L3). Plugin authors use it to test their own liv-based plugins.
--
-- Dev-only and **never vendored** (like liv.bundler): test code is not part of a
-- consumer plugin's shipped runtime require graph.
--
--   local test = require("liv.tester")
--   test.install()        -- optional: expose describe/it/assert as globals
--   describe("x", function() it("works", function() assert.equal(1, 1) end) end)
--   local passed, failed, skipped, failures = test.run()
--
-- A registry is an INSTANCE (`tester.new()`), so a test can build a hermetic
-- registry without touching the shared one; the module-level `describe`/`it`/…
-- names are a default instance. (No hidden singletons — a test of the framework
-- never perturbs the live run.)

local unpack = table.unpack or unpack

local M = {}

-- Marker key on the error VALUE raised by `pending()`, so the runner can tell a
-- deliberate skip from a real error. `pending()` raises a TABLE carrying this key;
-- the `run` message handler checks for it BEFORE the `tostring`/`traceback` that
-- would otherwise flatten the table into an opaque string.
local PENDING = "__liv_pending"

-- Per-test timing source. `os.clock` is portable across the bare interpreter (L1)
-- and inside either editor (L3), measuring CPU seconds — enough to rank tests and
-- flag slow ones. (A hi-res wall clock via liv.core would couple the framework to
-- the editor; per the plan, that optional refinement is left to the runner.)
local function clock()
  return os.clock()
end

-- --- Registry instance ------------------------------------------------------

-- Detect the `(name, opts, fn)` vs `(name, fn)` overload: when the second arg is
-- the body function, there are no opts.
local function split_args(opts_or_fn, fn)
  if type(opts_or_fn) == "function" then
    return {}, opts_or_fn
  end
  return opts_or_fn or {}, fn
end

-- Build a fresh, independent registry. Returns the busted-shaped surface closing
-- over its own tree, so instances never share state.
---@return table instance
function M.new()
  local root = {
    name = "",
    children = {},
    befores = {},
    afters = {},
    befores_all = {},
    afters_all = {},
    tags = {},
  }
  local stack = { root }

  -- The finally list of the test BODY currently executing, so `finally()` can
  -- register cleanup from inside it. Nil outside a body (registering then errors).
  local current_finally = nil

  local function current()
    return stack[#stack]
  end

  local instance = {}

  -- Register a group (`describe`/`context`). `opts.tags` (optional) attach tags
  -- that compose onto every nested test.
  local function describe(name, opts_or_fn, fn)
    local opts, body = split_args(opts_or_fn, fn)
    local node = {
      name = name,
      children = {},
      befores = {},
      afters = {},
      befores_all = {},
      afters_all = {},
      tags = opts.tags or {},
      only = opts.only or false,
      skip = opts.skip or false,
    }
    table.insert(current().children, node)
    table.insert(stack, node)
    body()
    table.remove(stack)
    return node
  end

  -- Register a single test (`it`). `opts.tags` (optional) attach tags.
  -- `origin` (optional `{ file, line }`) records where the test was declared, so
  -- a reporter can point at the source on failure; it is captured at the public
  -- `it()` boundary (see below) because the level seen from here is fixed.
  local function it(name, opts_or_fn, fn, origin)
    local opts, body = split_args(opts_or_fn, fn)
    table.insert(current().children, {
      name = name,
      fn = body,
      tags = opts.tags or {},
      only = opts.only or false,
      skip = opts.skip or false,
      file = origin and origin.file,
      line = origin and origin.line,
    })
  end

  -- Capture the declaration site of the caller's caller. `it("…", fn)` is invoked
  -- through a metamethod/variant wrapper, so the test body's source is two Lua
  -- frames above the inner `it`; `getinfo` from the public boundary sees that.
  local function origin_here()
    local info = debug.getinfo(3, "Sl")
    if not info then
      return nil
    end
    return { file = info.short_src, line = info.currentline }
  end

  -- `describe`/`it` are callable AND carry `.only`/`.skip` variants.
  instance.describe = setmetatable({
    only = function(name, opts_or_fn, fn)
      local opts, body = split_args(opts_or_fn, fn)
      opts.only = true
      return describe(name, opts, body)
    end,
    skip = function(name, opts_or_fn, fn)
      local opts, body = split_args(opts_or_fn, fn)
      opts.skip = true
      return describe(name, opts, body)
    end,
  }, {
    __call = function(_, name, opts_or_fn, fn)
      return describe(name, opts_or_fn, fn)
    end,
  })
  instance.context = instance.describe

  instance.it = setmetatable({
    only = function(name, opts_or_fn, fn)
      local opts, body = split_args(opts_or_fn, fn)
      opts.only = true
      return it(name, opts, body, origin_here())
    end,
    skip = function(name, opts_or_fn, fn)
      local opts, body = split_args(opts_or_fn, fn)
      opts.skip = true
      return it(name, opts, body, origin_here())
    end,
    -- `it.async(name, [opts,] afn)` registers a test whose body is an async
    -- function; the registered body drives it to completion synchronously, so an
    -- async leaf failure surfaces as an ordinary test failure.
    async = function(name, opts_or_fn, fn)
      local opts, body = split_args(opts_or_fn, fn)
      return it(name, opts, function()
        return require("liv.tester._async").drive(body)
      end, origin_here())
    end,
  }, {
    __call = function(_, name, opts_or_fn, fn)
      return it(name, opts_or_fn, fn, origin_here())
    end,
  })

  -- Drive an async function to completion synchronously and return its value
  -- (re-raising any error). The reusable pump authors call directly inside a
  -- plain `it` when they want async without `it.async`.
  function instance.async(fn)
    return require("liv.tester._async").drive(fn)
  end

  function instance.before_each(fn)
    table.insert(current().befores, fn)
  end

  function instance.after_each(fn)
    table.insert(current().afters, fn)
  end

  -- Describe-scoped one-time setup/teardown. `before_all` runs ONCE, lazily,
  -- just before the FIRST candidate test in the group's subtree executes;
  -- `after_all` runs ONCE after the group's subtree finishes — but only if its
  -- `before_all` actually fired, so an unfocused/filtered group runs neither.
  function instance.before_all(fn)
    table.insert(current().befores_all, fn)
  end

  function instance.after_all(fn)
    table.insert(current().afters_all, fn)
  end

  -- Register cleanup for the CURRENT test body; finallys run after the body in
  -- reverse registration order, whether the body passed, failed, or pended.
  function instance.finally(fn)
    if not current_finally then
      error("finally() called outside a test body", 2)
    end
    table.insert(current_finally, fn)
  end

  -- Called inside a test body: abandon it as SKIPPED (not failed). `reason` is
  -- carried for reporting.
  function instance.pending(reason)
    error({ [PENDING] = true, reason = reason }, 0)
  end

  -- Discard all registered tests (for a fresh run within one process).
  function instance.reset()
    root = {
      name = "",
      children = {},
      befores = {},
      afters = {},
      befores_all = {},
      afters_all = {},
      tags = {},
    }
    stack = { root }
  end

  -- Does any node in the tree carry `only`? (Then only focused subtrees run.)
  local function has_only(node)
    if node.only then
      return true
    end
    if node.children then
      for _, child in ipairs(node.children) do
        if has_only(child) then
          return true
        end
      end
    end
    return false
  end

  -- Run all registered tests.
  --
  -- A test is a CANDIDATE when it passes the focus (`only`) gate and the optional
  -- `opts.filter(title, tags)` selector; non-candidates simply don't run and are
  -- not counted. Among candidates, `.skip`/`describe.skip`/`pending()` make a test
  -- SKIPPED; otherwise it runs to passed/failed.
  --
  -- `reporter` drives an EVENT INTERFACE (all callbacks optional):
  --   on_run_start(ctx)            once, before any test
  --   on_suite_enter(name)         entering a NAMED group (root, name "", is skipped)
  --   on_suite_leave(name)         leaving that group
  --   on_test_start(name)          before a candidate runs
  --   on_test_end(report)          after it resolves; report =
  --                                { name, status, duration, error?, file?, line? }
  --   on_run_end(stats)            once, stats = { passed, failed, skipped, duration }
  -- (`on_layer_enter(layer)` is ALSO part of the reporter interface, but it is
  -- emitted by the CLI between layers — not by run(), which knows nothing of
  -- layers — so a reporter implements it for the L1/L3 section headers.)
  -- A bare FUNCTION is accepted for back-compat: it is treated as the old
  -- `on_progress(status)`, invoked per resolved candidate with the three-state tag.
  --
  -- Returns passed, failed, skipped, failures (list of { name, err, status }) — the
  -- shape predating the event interface, kept intact so existing callers are
  -- unaffected. `reporter` and `opts` are both optional.
  ---@param reporter? table|fun(status: string)
  ---@param opts? { filter?: fun(title: string, tags: string[]): boolean, seed?: integer }
  ---@return integer passed, integer failed, integer skipped, table[] failures
  function instance.run(reporter, opts)
    opts = opts or {}
    local filter = opts.filter
    local seed = opts.seed
    local focusing = has_only(root)
    local passed, failed, skipped, failures = 0, 0, 0, {}

    -- With `--seed`, shuffle each node's direct children (NOT a global flatten —
    -- flattening would break before_all laziness and before_each composition).
    -- Each node uses the same base seed, so the whole tree's order is reproducible
    -- from one seed printed by the runner.
    local function ordered_children(node)
      if seed == nil then
        return node.children
      end
      return require("liv.tester._shuffle").order(node.children, seed)
    end

    -- A bare function is the legacy on_progress; wrap it into the event shape so the
    -- driver below speaks only one protocol.
    local r = reporter or {}
    if type(reporter) == "function" then
      r = {
        on_test_end = function(report)
          reporter(report.status)
        end,
      }
    end
    local function emit(name, ...)
      local cb = r[name]
      if cb then
        cb(...)
      end
    end

    local run_start = clock()
    emit("on_run_start", {})

    -- Run every pending `before_all` from the outermost scope down to the
    -- innermost, LAZILY: invoked only just before the first candidate body in a
    -- group actually runs, and marked so each fires once. A scope whose tests are
    -- all non-candidates (filtered/unfocused) or skipped never reaches here, so
    -- its before_all (and matching after_all) never fire.
    local function fire_before_alls(scopes)
      for _, scope in ipairs(scopes) do
        if not scope.ran then
          scope.ran = true
          for _, f in ipairs(scope.befores_all) do
            f()
          end
        end
      end
    end

    local function run_node(node, prefix, befores, afters, tags, focused, skipped_branch, scopes)
      local path = prefix == "" and node.name or (prefix .. " " .. node.name)
      local named = node.name ~= ""
      if named then
        emit("on_suite_enter", node.name)
      end
      local befores2 = { unpack(befores) }
      for _, f in ipairs(node.befores) do
        table.insert(befores2, f)
      end
      local afters2 = { unpack(node.afters) }
      for _, f in ipairs(afters) do
        table.insert(afters2, f)
      end
      local tags2 = { unpack(tags) }
      for _, tag in ipairs(node.tags) do
        table.insert(tags2, tag)
      end

      -- This node's one-time scope, appended after the inherited ancestors so
      -- `fire_before_alls` walks outermost→innermost. `after_all` for this node
      -- runs at the END of this call (below) only if its before_all fired —
      -- recursion returns inner nodes first, giving innermost-first teardown.
      local scope = { befores_all = node.befores_all, afters_all = node.afters_all, ran = false }
      local scopes2 = { unpack(scopes) }
      scopes2[#scopes2 + 1] = scope

      for _, child in ipairs(ordered_children(node)) do
        local child_focused = focused or child.only
        local child_skipped = skipped_branch or child.skip
        if child.children then
          run_node(child, path, befores2, afters2, tags2, child_focused, child_skipped, scopes2)
        else
          local name = path .. " " .. child.name
          local child_tags = { unpack(tags2) }
          for _, tag in ipairs(child.tags) do
            table.insert(child_tags, tag)
          end

          local candidate = (not focusing) or child_focused
          if candidate and filter then
            candidate = filter(name, child_tags)
          end

          if candidate then
            emit("on_test_start", name)
            local started = clock()
            local report = { name = name, file = child.file, line = child.line }
            if child_skipped then
              skipped = skipped + 1
              report.status = "skipped"
            else
              -- Fire any pending before_all in ancestor scopes before the first
              -- real body so setup precedes before_each.
              fire_before_alls(scopes2)
              for _, f in ipairs(befores2) do
                f()
              end
              -- Per-test finally registry: `finally()` pushes here while the body
              -- runs; we drain it in reverse afterward, regardless of outcome.
              local finallys = {}
              local prev_finally = current_finally
              current_finally = finallys
              local is_pending = false
              local ok, err = xpcall(child.fn, function(e)
                if type(e) == "table" and e[PENDING] then
                  is_pending = true
                  return e
                end
                return debug.traceback(tostring(e), 2)
              end)
              current_finally = prev_finally
              -- Run finallys (reverse registration order). A finally that errors
              -- turns an otherwise-passing/pending test into a failure.
              local finally_err = nil
              for i = #finallys, 1, -1 do
                local fok, ferr = xpcall(finallys[i], function(e)
                  return debug.traceback(tostring(e), 2)
                end)
                if not fok and not finally_err then
                  finally_err = ferr
                end
              end
              for _, f in ipairs(afters2) do
                pcall(f)
              end
              if finally_err and (ok or is_pending) then
                -- A finally failure overrides a passed/pending outcome.
                ok, is_pending, err = false, false, finally_err
              end
              if is_pending then
                skipped = skipped + 1
                report.status = "skipped"
                report.reason = type(err) == "table" and err.reason or nil
              elseif ok then
                passed = passed + 1
                report.status = "passed"
              else
                failed = failed + 1
                report.status = "failed"
                report.error = err
                -- Carry the it() declaration origin (file:line) on the failure
                -- record too, not just the reporter event, so the CLI's
                -- `--failed` state file records where the test lives.
                failures[#failures + 1] = {
                  name = name,
                  err = err,
                  status = "failed",
                  file = child.file,
                  line = child.line,
                }
              end
            end
            report.duration = clock() - started
            emit("on_test_end", report)
          end
        end
      end

      -- Teardown for THIS scope, only if its setup fired (recursion already ran
      -- inner scopes' after_all, so this is the outer-of-its-children turn).
      if scope.ran then
        for _, f in ipairs(scope.afters_all) do
          pcall(f)
        end
      end

      if named then
        emit("on_suite_leave", node.name)
      end
    end

    run_node(root, "", {}, {}, {}, false, false, {})
    emit("on_run_end", {
      passed = passed,
      failed = failed,
      skipped = skipped,
      duration = clock() - run_start,
    })
    return passed, failed, skipped, failures
  end

  -- Enumerate the full titles of the CANDIDATE tests WITHOUT running any body —
  -- the same focus + selector gate as `run`, so `--list` previews exactly what a
  -- run would execute. `opts.filter` is the optional selector predicate; tags
  -- compose like in `run`. Skipped (`it.skip`/`describe.skip`) tests are still
  -- candidates here (they would be reported by a run), only `pending()` — which is
  -- a body decision — cannot be known without executing, so it is not reflected.
  ---@param opts? { filter?: fun(title: string, tags: string[]): boolean }
  ---@return string[] names
  function instance.list(opts)
    opts = opts or {}
    local filter = opts.filter
    local focusing = has_only(root)
    local names = {}

    local function walk(node, prefix, tags, focused)
      local path = prefix == "" and node.name or (prefix .. " " .. node.name)
      local tags2 = { unpack(tags) }
      for _, tag in ipairs(node.tags) do
        table.insert(tags2, tag)
      end
      for _, child in ipairs(node.children) do
        local child_focused = focused or child.only
        if child.children then
          walk(child, path, tags2, child_focused)
        else
          local name = path .. " " .. child.name
          local child_tags = { unpack(tags2) }
          for _, tag in ipairs(child.tags) do
            table.insert(child_tags, tag)
          end
          local candidate = (not focusing) or child_focused
          if candidate and filter then
            candidate = filter(name, child_tags)
          end
          if candidate then
            names[#names + 1] = name
          end
        end
      end
    end

    walk(root, "", {}, false)
    return names
  end

  return instance
end

-- --- Default module-level instance ------------------------------------------

local default = M.new()

M.describe = default.describe
M.context = default.context
M.it = default.it
M.async = default.async
M.before_each = default.before_each
M.after_each = default.after_each
M.before_all = default.before_all
M.after_all = default.after_all
M.finally = default.finally
M.pending = default.pending
M.reset = default.reset
M.run = default.run
M.list = default.list

-- --- Assertions (luassert-shaped subset) -----------------------------------

local function is_table(v)
  return type(v) == "table"
end

local function deep_equal(a, b)
  if a == b then
    return true
  end
  if not is_table(a) or not is_table(b) then
    return false
  end
  for k, v in pairs(a) do
    if not deep_equal(v, b[k]) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

local function show(v)
  if type(v) == "string" then
    return string.format("%q", v)
  end
  if not is_table(v) then
    return tostring(v)
  end
  local parts = {}
  for k, val in pairs(v) do
    table.insert(parts, tostring(k) .. "=" .. show(val))
  end
  table.sort(parts)
  return "{" .. table.concat(parts, ", ") .. "}"
end

-- Find the FIRST path where two values deep-diverge, returned as a dotted key
-- path plus the two leaf values, so `same` can point at exactly what differs
-- instead of dumping both whole tables. Returns nil when equal. `prefix` threads
-- the path down the recursion.
local function diff_path(a, b, prefix)
  prefix = prefix or ""
  if a == b then
    return nil
  end
  if not is_table(a) or not is_table(b) then
    return prefix == "" and "value" or prefix, a, b
  end
  for k, v in pairs(a) do
    local here = prefix == "" and tostring(k) or (prefix .. "." .. tostring(k))
    local path, av, bv = diff_path(v, b[k], here)
    if path then
      return path, av, bv
    end
  end
  for k, v in pairs(b) do
    if a[k] == nil then
      local here = prefix == "" and tostring(k) or (prefix .. "." .. tostring(k))
      return here, nil, v
    end
  end
  return nil
end

local function fail(msg)
  error(msg, 3)
end

-- A luassert-shaped, callable assertion object. Calling it asserts truthiness;
-- the methods assert specific conditions and raise (pcall-able) on failure.
---@class liv.tester.Assert
---@field equal fun(expected: any, got: any, msg?: string) Assert `expected == got`.
---@field equals fun(expected: any, got: any, msg?: string) Alias of `equal`.
---@field same fun(expected: any, got: any, msg?: string) Assert deep equality.
---@field is_true fun(v: any, msg?: string) Assert `v == true`.
---@field is_false fun(v: any, msg?: string) Assert `v == false`.
---@field is_nil fun(v: any, msg?: string) Assert `v == nil`.
---@field is_not_nil fun(v: any, msg?: string) Assert `v ~= nil`.
---@field is_table fun(v: any, msg?: string) Assert `v` is a table.
---@field is_function fun(v: any, msg?: string) Assert `v` is a function.
---@field is_string fun(v: any, msg?: string) Assert `v` is a string.
---@field is_number fun(v: any, msg?: string) Assert `v` is a number.
---@field is_boolean fun(v: any, msg?: string) Assert `v` is a boolean.
---@field has_error fun(fn: fun(), expected?: string): any Assert `fn` errors (optionally containing `expected`); returns the error.
---@field has_error_matching fun(fn: fun(), pattern: string): any Assert `fn` errors with a message matching `pattern` (a Lua pattern); returns the error.
---@field has_no_error fun(fn: fun()): any Assert `fn` does not error; returns its result.
---@field match fun(value: string, pattern: string) Assert `value` matches the Lua `pattern`.
---@field length_of fun(value: string|table, n: integer) Assert `value` has `#`-length `n`.
---@field includes fun(value: string|table, needle: any) Assert `value` includes `needle` (substring or sequence element).
---@field contains fun(value: string|table, needle: any) Alias of `includes`.
---@field truthy fun(v: any, msg?: string) Assert `v` is neither `nil` nor `false`.
---@field falsy fun(v: any, msg?: string) Assert `v` is `nil` or `false`.
---@field are table Nested: `equal`/`equals`/`same`.
---@field is table Nested: `truthy`/`falsy`/`equal`/`same`/`nil`.
---@field are_not table Nested: `equal`.
---@field is_not table Nested: `nil`/`equal`.
---@overload fun(v: any, msg?: string): any

local A = {}

function A.equal(expected, got, msg)
  if expected ~= got then
    fail((msg or "values differ") .. ": expected " .. show(expected) .. ", got " .. show(got))
  end
end

A.equals = A.equal

function A.same(expected, got, msg)
  if not deep_equal(expected, got) then
    -- Point at the first diverging key path (with its two leaf values) so the
    -- reader sees WHICH part differs, then still show the full values for context.
    local path, ev, gv = diff_path(expected, got)
    local at = path and (" at " .. path .. " (expected " .. show(ev) .. ", got " .. show(gv) .. ")")
      or ""
    fail((msg or "tables differ") .. at .. ": expected " .. show(expected) .. ", got " .. show(got))
  end
end

function A.is_true(v, msg)
  if v ~= true then
    fail((msg or "expected true") .. ", got " .. show(v))
  end
end

function A.is_false(v, msg)
  if v ~= false then
    fail((msg or "expected false") .. ", got " .. show(v))
  end
end

function A.is_nil(v, msg)
  if v ~= nil then
    fail((msg or "expected nil") .. ", got " .. show(v))
  end
end

function A.is_not_nil(v, msg)
  if v == nil then
    fail(msg or "expected non-nil")
  end
end

local function type_assert(name)
  return function(v, msg)
    if type(v) ~= name then
      fail((msg or ("expected " .. name)) .. ", got " .. type(v))
    end
  end
end

A.is_table = type_assert("table")
A.is_function = type_assert("function")
A.is_string = type_assert("string")
A.is_number = type_assert("number")
A.is_boolean = type_assert("boolean")

function A.has_error(fn, expected)
  local ok, err = pcall(fn)
  if ok then
    fail("expected an error, but none was raised")
  end
  if expected ~= nil then
    local got = tostring(err)
    if not string.find(got, expected, 1, true) then
      fail("error mismatch: expected to contain " .. show(expected) .. ", got " .. show(got))
    end
  end
  return err
end

-- Assert `fn` errors AND its message matches the Lua `pattern` (a regex-ish
-- magic-pattern match, NOT the plain substring `has_error` uses). Returns the
-- raised error so the caller can inspect it further.
function A.has_error_matching(fn, pattern)
  local ok, err = pcall(fn)
  if ok then
    fail("expected an error, but none was raised")
  end
  local got = tostring(err)
  if not string.find(got, pattern) then
    fail("error mismatch: expected to match " .. show(pattern) .. ", got " .. show(got))
  end
  return err
end

-- Assert `fn` does NOT error; returns whatever `fn` returned, so callers can use
-- it both as a guard and to capture the value.
function A.has_no_error(fn)
  local ok, ret = pcall(fn)
  if not ok then
    fail("expected no error, but one was raised: " .. show(tostring(ret)))
  end
  return ret
end

-- Assert the subject (a string or sequence) MATCHES `pattern` (a Lua pattern).
function A.match(value, pattern)
  if type(value) ~= "string" then
    fail("expected a string to match against, got " .. type(value))
  end
  if not string.find(value, pattern) then
    fail("expected " .. show(value) .. " to match pattern " .. show(pattern))
  end
end

-- Assert a string or sequence has exactly `n` elements (`#`-length).
function A.length_of(value, n)
  local t = type(value)
  if t ~= "string" and t ~= "table" then
    fail("expected a string or table for length, got " .. t)
  end
  local got = #value
  if got ~= n then
    fail("length mismatch: expected " .. show(n) .. ", got " .. show(got))
  end
end

-- Assert `value` includes `needle`: a substring of a string, or an element
-- (deep-equal) of a sequence. `contains` is an alias.
function A.includes(value, needle)
  if type(value) == "string" then
    if type(needle) ~= "string" then
      fail("expected a string needle for a string subject, got " .. type(needle))
    end
    if not string.find(value, needle, 1, true) then
      fail("expected " .. show(value) .. " to include " .. show(needle))
    end
    return
  end
  if type(value) == "table" then
    for _, item in ipairs(value) do
      if deep_equal(item, needle) then
        return
      end
    end
    fail("expected " .. show(value) .. " to include " .. show(needle))
  end
  fail("expected a string or table subject for includes, got " .. type(value))
end

A.contains = A.includes

-- Truthy/falsy as top-level matchers, DISTINCT from the strict `is_true`/
-- `is_false`: `truthy` accepts any value that is neither `nil` nor `false`.
function A.truthy(v, msg)
  if not v then
    fail((msg or "expected truthy") .. ", got " .. show(v))
  end
end

function A.falsy(v, msg)
  if v then
    fail((msg or "expected falsy") .. ", got " .. show(v))
  end
end

A.are = { equal = A.equal, equals = A.equal, same = A.same }
A.is = {
  truthy = A.truthy,
  falsy = A.falsy,
  equal = A.equal,
  same = A.same,
  ["nil"] = A.is_nil,
}
A.are_not = {
  equal = function(expected, got, msg)
    if expected == got then
      fail((msg or "expected values to differ") .. ", both " .. show(got))
    end
  end,
}
A.is_not = {
  ["nil"] = A.is_not_nil,
  equal = A.are_not.equal,
}

---@type liv.tester.Assert
M.assert = setmetatable(A, {
  __call = function(_, v, msg)
    if not v then
      fail(msg or "assertion failed")
    end
    return v
  end,
})

-- Install the busted-style names into a table (default the global env), so spec
-- files can use bare `describe`/`it`/`assert` without requiring this module.
---@param env? table Target table to install into (defaults to `_G`).
---@return table module This module (`M`), for chaining.
function M.install(env)
  env = env or _G
  env.describe = M.describe
  env.context = M.context
  env.it = M.it
  env.before_each = M.before_each
  env.after_each = M.after_each
  env.before_all = M.before_all
  env.after_all = M.after_all
  env.finally = M.finally
  env.pending = M.pending
  env.assert = M.assert
  return M
end

-- --- Result record ----------------------------------------------------------

-- A failed test record.
---@class liv.tester.Failure
---@field name string Fully-qualified test name.
---@field err string Error message (with traceback).
---@field status string Always `'failed'` (the three-state tag for this record).

return M
