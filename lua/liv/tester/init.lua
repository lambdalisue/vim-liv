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
--   local passed, failed, failures = test.run()

local unpack = table.unpack or unpack

local M = {}

local root = { name = "", children = {}, befores = {}, afters = {} }
local stack = { root }

local function current()
  return stack[#stack]
end

-- Register a group of tests (a `describe`/`context` block).
---@param name string Group name.
---@param fn fun() Body registering nested groups/tests.
function M.describe(name, fn)
  local node = { name = name, children = {}, befores = {}, afters = {} }
  table.insert(current().children, node)
  table.insert(stack, node)
  fn()
  table.remove(stack)
end

M.context = M.describe

-- Register a single test case.
---@param name string Test name.
---@param fn fun() Test body.
function M.it(name, fn)
  table.insert(current().children, { name = name, fn = fn })
end

-- Register a hook run before each test in the current group.
---@param fn fun() Hook body.
function M.before_each(fn)
  table.insert(current().befores, fn)
end

-- Register a hook run after each test in the current group.
---@param fn fun() Hook body.
function M.after_each(fn)
  table.insert(current().afters, fn)
end

-- Discard all registered tests (for a fresh run within one process).
function M.reset()
  root = { name = "", children = {}, befores = {}, afters = {} }
  stack = { root }
end

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
    fail((msg or "tables differ") .. ": expected " .. show(expected) .. ", got " .. show(got))
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

A.are = { equal = A.equal, equals = A.equal, same = A.same }
A.is = {
  truthy = function(v, msg)
    if not v then
      fail((msg or "expected truthy") .. ", got " .. show(v))
    end
  end,
  falsy = function(v, msg)
    if v then
      fail((msg or "expected falsy") .. ", got " .. show(v))
    end
  end,
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
  env.assert = M.assert
  return M
end

-- --- Execution -------------------------------------------------------------

-- A failed test record.
---@class liv.tester.Failure
---@field name string Fully-qualified test name.
---@field err string Error message (with traceback).

-- Run all registered tests. Returns passed, failed, failures (list of
-- {name, err}). `on_progress(ok)` is called per test for live output (optional).
---@param on_progress? fun(ok: boolean) Called per test with its pass/fail result.
---@return integer passed Number of passing tests.
---@return integer failed Number of failing tests.
---@return liv.tester.Failure[] failures Records for each failing test.
function M.run(on_progress)
  local passed, failed, failures = 0, 0, {}

  local function run_node(node, prefix, befores, afters)
    local path = prefix == "" and node.name or (prefix .. " " .. node.name)
    local befores2 = { unpack(befores) }
    for _, f in ipairs(node.befores) do
      table.insert(befores2, f)
    end
    local afters2 = { unpack(node.afters) }
    for _, f in ipairs(afters) do
      table.insert(afters2, f)
    end

    for _, child in ipairs(node.children) do
      if child.children then
        run_node(child, path, befores2, afters2)
      else
        local name = path .. " " .. child.name
        for _, f in ipairs(befores2) do
          f()
        end
        local ok, err = xpcall(child.fn, function(e)
          return debug.traceback(tostring(e), 2)
        end)
        for _, f in ipairs(afters2) do
          pcall(f)
        end
        if ok then
          passed = passed + 1
        else
          failed = failed + 1
          table.insert(failures, { name = name, err = err })
        end
        if on_progress then
          on_progress(ok)
        end
      end
    end
  end

  run_node(root, "", {}, {})
  return passed, failed, failures
end

return M
