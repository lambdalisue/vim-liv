-- liv.generator.function.generate — orchestrate function codegen (pure Lua).
-- Split parsed Vim/Neovim function entries into common / vim-only / nvim-only and
-- emit one LuaLS annotation file per namespace. Returns repo-relative path ->
-- content. Functions carry no runtime metadata (the runtime forwards any name to
-- core.call), so only annotation files are produced.
local format = require("liv.generator.function.format")

local M = {}

local function name_set(entries)
  local s = {}
  for _, e in ipairs(entries) do
    s[e.name] = true
  end
  return s
end

local function filter(entries, keep)
  local r = {}
  for _, e in ipairs(entries) do
    if keep(e.name) then
      r[#r + 1] = e
    end
  end
  return r
end

---@param vim_entries liv.generator.function.Entry[] Parsed Vim function entries.
---@param nvim_entries liv.generator.function.Entry[] Parsed Neovim function entries.
---@return table<string, string> files Map of repo-relative path -> file content.
function M.generate(vim_entries, nvim_entries)
  local vset, nset = name_set(vim_entries), name_set(nvim_entries)
  local common = filter(vim_entries, function(n)
    return nset[n]
  end)
  local vim_only = filter(vim_entries, function(n)
    return not nset[n]
  end)
  local nvim_only = filter(nvim_entries, function(n)
    return not vset[n]
  end)

  return {
    ["lua/liv/std/function/_generated_annotations.lua"] = format(common, "liv.std.function.Common"),
    ["lua/liv/std/function/vim/_generated_annotations.lua"] = format(vim_only, "liv.std.function.Vim"),
    ["lua/liv/std/function/nvim/_generated_annotations.lua"] = format(nvim_only, "liv.std.function.Nvim"),
  }
end

return setmetatable(M, {
  __call = function(_, vim_entries, nvim_entries)
    return M.generate(vim_entries, nvim_entries)
  end,
})
