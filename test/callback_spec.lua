-- L3 integration test for liv.std.callback (spec 0006), on both editors. Proves a
-- Lua handler bound via function_name() is reachable as an editor function NAME and
-- usable as a buffer-local 'omnifunc': the editor invokes it as Func(findstart,
-- base) and the Lua return marshals back -- including the two shapes omnifunc needs
-- (a List of Dicts, and an empty List). And proves the general named() form binds a
-- Lua handler callable from any vimscript string context with ARBITRARY args.
--
-- The bound name is editor-shaped (a `v:lua.…` path on Neovim, a `LivFunc…`/
-- `LivNamed…` function on Vim). Both are valid as the head of a call EXPRESSION on
-- their editor, so the test invokes through core.eval(name .. "(...)") -- the same
-- way the editor evaluates an 'omnifunc' string -- rather than vim.call (which does
-- not accept a v:lua path as a function name).
local callback = require("liv.std.callback")
local option = require("liv.std.option")
local buffer = require("liv.std.buffer")
local window = require("liv.std.window")
local core = require("liv.core")

--- Invoke a bound omnifunc by name as Func(findstart, base) via editor eval.
local function invoke(name, findstart, base)
  return core.eval(string.format("%s(%d, %s)", name, findstart, vim.fn.string(base)))
end

describe("liv.std.callback (L3)", function()
  it("binds a Lua handler to an omnifunc that returns a list of dicts", function()
    local seen = {}
    local name = callback.function_name(function(findstart, base)
      seen.findstart = findstart
      seen.base = base
      if findstart == 1 then
        return 0
      end
      return {
        { word = "/clear", menu = "Start a new conversation", kind = "Slash" },
        { word = "/compact", menu = "Summarize the conversation", kind = "Slash" },
      }
    end)

    local bufnr = buffer.create({ listed = false, scratch = true })
    core.cmd("buffer " .. bufnr)
    -- The seam's product is a valid value for the omnifunc option on both editors.
    option.b.set("omnifunc", name)
    assert.equal(name, option.b.get("omnifunc"))

    -- findstart path: the editor calls Func(1, "") and expects a column.
    local start = invoke(name, 1, "")
    assert.equal(0, start)
    assert.equal(1, seen.findstart)

    -- completion path: Func(0, base) returns the candidate List of Dicts.
    local items = invoke(name, 0, "/c")
    assert.equal("/c", seen.base)
    assert.equal(2, #items)
    assert.equal("/clear", items[1].word)
    assert.equal("Slash", items[1].kind)
    assert.equal("/compact", items[2].word)

    pcall(window.close, window.current())
  end)

  it("round-trips an empty completion list as an empty List (not a Dict)", function()
    local name = callback.function_name(function(findstart, _base)
      if findstart == 1 then
        return -3
      end
      return {}
    end)
    local items = invoke(name, 0, "zzz")
    assert.same({}, items)
  end)

  it("release unregisters the bound function (and is idempotent)", function()
    local hits = 0
    local name = callback.function_name(function(_a, _b)
      hits = hits + 1
      return 0
    end)
    -- Bound and callable before release.
    invoke(name, 1, "")
    assert.equal(1, hits)

    callback.release(name)
    -- After release the name no longer resolves to the handler; invoking it
    -- raises (so guard with pcall) and the handler is not called again.
    pcall(invoke, name, 1, "")
    assert.equal(1, hits)

    -- Idempotent: releasing a second time does not raise.
    local ok = pcall(callback.release, name)
    assert.is_true(ok)
  end)

  it("named binds a Lua handler callable from vimscript with arbitrary args", function()
    -- The general form: bind a plain Lua function and call it from vimscript with
    -- two marshaled args; the marshaled return crosses back.
    local name = callback.named(function(a, b)
      return a + b
    end)
    assert.equal(5, core.eval(name .. "(2, 3)"))
  end)

  it("named forwards zero args and marshals a returned list back", function()
    -- A zero-arg call proves named is genuinely variadic (not the 2-arity
    -- omnifunc forwarder), and a returned Lua list reaches vimscript as a List
    -- usable from an expression.
    local name = callback.named(function()
      return core.list({ "x", "y" })
    end)
    local items = core.eval(name .. "()")
    assert.same({ "x", "y" }, items)
  end)

  it("release unregisters a named binding (and is idempotent)", function()
    local hits = 0
    local name = callback.named(function()
      hits = hits + 1
      return hits
    end)
    -- Bound and callable before release.
    assert.equal(1, core.eval(name .. "()"))

    callback.release(name)
    -- After release the name no longer resolves to the handler; invoking it
    -- raises (so guard with pcall) and the handler is not called again.
    pcall(core.eval, name .. "()")
    assert.equal(1, hits)

    -- Idempotent: releasing a second time does not raise.
    local ok = pcall(callback.release, name)
    assert.is_true(ok)
  end)
end)
