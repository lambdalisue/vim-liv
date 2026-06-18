-- liv.generator.option.generate — orchestrate the option codegen (pure Lua).
-- Given parsed Vim and Neovim option defs, split them into common / vim-only /
-- nvim-only and emit each namespace's metadata + LuaLS annotation files. Returns
-- a map of repo-relative path -> file content (the bin writes them).
local format = require("liv.generator.option.format")

local M = {}

local function by_name(defs)
  local m = {}
  for _, d in ipairs(defs) do
    m[d.name] = d
  end
  return m
end

---@param vim_defs liv.generator.option.Def[] Parsed Vim option definitions.
---@param nvim_defs liv.generator.option.Def[] Parsed Neovim option definitions.
---@return table<string, string> files Map of repo-relative path -> file content.
function M.generate(vim_defs, nvim_defs)
  local vmap, nmap = by_name(vim_defs), by_name(nvim_defs)
  local common, vim_only, nvim_only = {}, {}, {}

  for name, d in pairs(vmap) do
    if nmap[name] then
      common[#common + 1] = d -- present in both: use the Vim def
    else
      vim_only[#vim_only + 1] = d
    end
  end
  for name, d in pairs(nmap) do
    if not vmap[name] then
      nvim_only[#nvim_only + 1] = d
    end
  end

  local c = format(common, "liv.std.option.Common")
  local v = format(vim_only, "liv.std.option.Vim")
  local n = format(nvim_only, "liv.std.option.Nvim")

  return {
    ["lua/liv/std/option/_generated.lua"] = c.meta,
    ["lua/liv/std/option/_generated_annotations.lua"] = c.annotations,
    ["lua/liv/std/option/vim/_generated.lua"] = v.meta,
    ["lua/liv/std/option/vim/_generated_annotations.lua"] = v.annotations,
    ["lua/liv/std/option/nvim/_generated.lua"] = n.meta,
    ["lua/liv/std/option/nvim/_generated_annotations.lua"] = n.annotations,
  }
end

return setmetatable(M, {
  __call = function(_, vim_defs, nvim_defs)
    return M.generate(vim_defs, nvim_defs)
  end,
})
