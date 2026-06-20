-- L1 structural test pinning the SHAPE of the committed liv.std.option runtime
-- metadata. The runtime artifact must stay a slim SET of boolean option names
-- (each value plainly `true`, no {type,scope} record) so a consumer that bundles
-- liv.std.option vendors only the boolean lookup, not the full option table. The
-- complete {type,scope} table lives in the require-free LuaLS annotations and is
-- not asserted here. These tables are pure Lua, so they load with no editor.
local function load_runtime_meta(path)
  local chunk = assert(loadfile(path))
  return chunk()
end

describe("liv.std.option runtime metadata (committed)", function()
  local common = load_runtime_meta("lua/liv/std/option/_generated.lua")
  local vim_only = load_runtime_meta("lua/liv/std/option/vim/_generated.lua")
  local nvim_only = load_runtime_meta("lua/liv/std/option/nvim/_generated.lua")

  it("is a SET: every entry maps to the literal `true`, never a record", function()
    for _, meta in ipairs({ common, vim_only, nvim_only }) do
      for name, value in pairs(meta) do
        assert.equal(true, value, "expected " .. tostring(name) .. " to be a boolean-set entry")
      end
    end
  end)

  it("contains a known boolean option (expandtab)", function()
    assert.equal(true, common.expandtab)
  end)

  it("omits non-boolean options (textwidth number, background string)", function()
    assert.is_nil(common.textwidth)
    assert.is_nil(common.background)
  end)
end)
