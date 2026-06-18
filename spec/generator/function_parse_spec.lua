-- L1 unit test for liv.generator function-doc parsing (pure Lua). Two sources,
-- as in @denops/std: function names + signatures come from the `*name()*` tag
-- lines (present in BOTH Vim and Neovim docs), and the return type comes from the
-- Vim-style function-list table (`name(args)<TAB>TYPE<TAB>desc`); a function with
-- a tag but no table entry (e.g. Neovim-only) gets return type `any`.
local parse = require("liv.generator.function.parse")
local TAB = "\t"

local function find(entries, name)
  for _, e in ipairs(entries) do
    if e.name == name then
      return e
    end
  end
end

describe("liv.generator.function.parse", function()
  it("takes the signature from the tag line and the type from the list table", function()
    local got = parse(table.concat({
      "abs({expr})" .. TAB .. "Float or Number" .. TAB .. "absolute value", -- list table
      "Details:",
      "abs({expr})" .. TAB .. TAB .. "*abs()*", -- tag block
      "    Return the absolute value of {expr}.",
    }, "\n"))
    assert.same({ { name = "abs", params = { { name = "expr", optional = false } }, rettype = "number" } }, got)
  end)

  it("parses a tagged function with no table entry as return type any (Neovim case)", function()
    local got = parse("foo({x})" .. TAB .. TAB .. "*foo()*")
    assert.same({ { name = "foo", params = { { name = "x", optional = false } }, rettype = "any" } }, got)
  end)

  it("parses optional params from the tag signature", function()
    local got = parse("has({feature} [, {check}])" .. TAB .. "*has()*")
    assert.same({
      { name = "feature", optional = false },
      { name = "check", optional = true },
    }, find(got, "has").params)
  end)

  it("parses a no-argument function and maps Number to integer", function()
    local got = parse(table.concat({
      "localtime()" .. TAB .. "Number" .. TAB .. "current time",
      "localtime()" .. TAB .. TAB .. "*localtime()*",
    }, "\n"))
    assert.same({ { name = "localtime", params = {}, rettype = "integer" } }, got)
  end)

  it("finds the signature when the tag is on its own line (Vim getline case)", function()
    -- In Vim, a previous example's `<` can push the *getline()* tag onto its own
    -- line, with the real signature on the next line. The nearest signature wins.
    local got = parse(table.concat({
      "getline({lnum})" .. TAB .. "String" .. TAB .. "line", -- list table (far above)
      string.rep("filler\n", 5),
      "<" .. TAB .. TAB .. "*getline()*", -- tag on its own line
      "getline({lnum} [, {end}])", -- signature on the next line
      "    Get the line.",
    }, "\n"))
    local e = find(got, "getline")
    assert.is_not_nil(e)
    assert.equal("string", e.rettype)
    assert.equal("lnum", e.params[1].name)
    assert.equal("end", e.params[2].name)
    assert.is_true(e.params[2].optional)
  end)

  it("ignores cross-references and prose (only real *name()* signature lines)", function()
    local got = parse(table.concat({
      "See |getline()| and *note* for details.",
      "this mentions foo({bar}) inline but is prose",
    }, "\n"))
    assert.same({}, got)
  end)
end)
