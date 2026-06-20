-- L1 unit test for bundler static analysis (spec 0008).
-- Pure: a resolver maps module name -> source string, so no filesystem/editor.
local analyze = require("liv.bundler.analyze")

describe("analyze.requires", function()
  it("extracts double- and single-quoted literal requires", function()
    local src = [[
      local a = require("liv.core")
      local b = require('liv.lua.path')
    ]]
    assert.same({ "liv.core", "liv.lua.path" }, analyze.requires(src))
  end)

  it("extracts requires without parentheses", function()
    local src = [[
      local a = require "foo.bar"
      local b = require 'baz'
    ]]
    assert.same({ "foo.bar", "baz" }, analyze.requires(src))
  end)

  it("ignores dynamic (non-literal) requires", function()
    local src = [[
      local name = "x"
      local a = require(name)
      local b = require("kept")
    ]]
    assert.same({ "kept" }, analyze.requires(src))
  end)

  it("dedupes while preserving first-seen order", function()
    local src = [[
      require("a"); require("b"); require("a")
    ]]
    assert.same({ "a", "b" }, analyze.requires(src))
  end)
end)

describe("analyze.has_dynamic", function()
  it("is true when a require has a non-literal argument", function()
    assert.is_true(analyze.has_dynamic([[require(modname)]]))
  end)

  it("is false when all requires are string literals", function()
    assert.is_false(analyze.has_dynamic([[require("a"); require 'b']]))
  end)
end)

describe("analyze.closure", function()
  -- A tiny module graph encoded as name -> source.
  local function graph(map)
    return function(name)
      return map[name]
    end
  end

  it("computes the transitive closure from the roots", function()
    local resolve = graph({
      a = [[require("b"); require("c")]],
      b = [[require("d")]],
      c = [[require("d")]],
      d = [[-- leaf]],
    })
    local result = analyze.closure({ "a" }, resolve)
    assert.same({ "a", "b", "c", "d" }, result.modules)
    assert.same({}, result.external)
  end)

  it("terminates on dependency cycles", function()
    local resolve = graph({
      a = [[require("b")]],
      b = [[require("a")]],
    })
    local result = analyze.closure({ "a" }, resolve)
    assert.same({ "a", "b" }, result.modules)
  end)

  it("records unresolvable modules as external (not traversed)", function()
    local resolve = graph({
      a = [[require("b"); require("ext.lib")]],
      b = [[-- leaf]],
    })
    local result = analyze.closure({ "a" }, resolve)
    assert.same({ "a", "b" }, result.modules)
    assert.same({ "ext.lib" }, result.external)
  end)
end)

-- Tree-shaking regression: the bundler closure is file-grained, so a leaf that
-- requires only its sibling leaf (never the barrel) must NOT drag the rest of
-- the family in. These read the REAL source from disk (cwd = repo root) so they
-- assert the actual require graph, not a hand-written stand-in.
describe("analyze.closure tree-shaking (real sources)", function()
  -- Resolve a liv module name to its on-disk source: lua/<path>.lua, else
  -- lua/<path>/init.lua. Returns nil for anything not under lua/ (recorded as
  -- external, not traversed) — the assertions only care about exclusion.
  local function file_resolve(name)
    local rel = "lua/" .. name:gsub("%.", "/")
    for _, p in ipairs({ rel .. ".lua", rel .. "/init.lua" }) do
      local f = io.open(p, "rb")
      if f then
        local s = f:read("*a")
        f:close()
        return s
      end
    end
    return nil
  end

  local function module_set(roots)
    local set = {}
    for _, m in ipairs(analyze.closure(roots, file_resolve).modules) do
      set[m] = true
    end
    return set
  end

  it("uri.percent pulls nothing else: not url, not query, not the barrel", function()
    local set = module_set({ "liv.lua.uri.percent" })
    assert.is_true(set["liv.lua.uri.percent"])
    -- percent is the zero-dependency concern; it must stand entirely alone.
    assert.is_nil(set["liv.lua.uri.url"])
    assert.is_nil(set["liv.lua.uri.query"])
    assert.is_nil(set["liv.lua.uri"])
  end)

  it("uri.query pulls the percent leaf but NOT url or the barrel", function()
    local set = module_set({ "liv.lua.uri.query" })
    assert.is_true(set["liv.lua.uri.query"])
    -- positive control: the query codec percent-encodes keys/values via percent.
    assert.is_true(set["liv.lua.uri.percent"])
    -- parse/build and the barrel stay out of a query-only bundle
    assert.is_nil(set["liv.lua.uri.url"])
    assert.is_nil(set["liv.lua.uri"])
  end)
end)
