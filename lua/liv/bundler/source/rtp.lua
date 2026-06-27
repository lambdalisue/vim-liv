-- Bundler `rtp` source resolver (spec 0008/0009): resolve modules from the lua/
-- directories on Vim/Neovim's &runtimepath. Reading &runtimepath needs the editor,
-- but that read is done by the caller (the :LivBundle shim) and the path string is
-- passed in here — so this module stays pure and L1-testable: it is just the
-- `path` resolver over several lua/ roots, first match winning.
local path = require("liv.bundler.source.path")

local M = {}

-- Split a &runtimepath string into the lua/ roots to search.
---@param runtimepath string comma-separated &runtimepath
---@return string[] roots the `<entry>/lua` directories
function M.lua_roots(runtimepath)
  local roots = {}
  for entry in runtimepath:gmatch("[^,]+") do
    roots[#roots + 1] = entry .. "/lua"
  end
  return roots
end

---@param roots string[] lua/ directories to search, in order
---@param fs { exists: fun(p: string): boolean, read: fun(p: string): string? }
---@return { locate: fun(name: string): string?, read: fun(name: string): string?, read_raw: fun(rel: string, name?: string): string?, manifest: fun(name: string): table? }
function M.resolver(roots, fs)
  local resolvers = {}
  for _, root in ipairs(roots) do
    resolvers[#resolvers + 1] = path.resolver(root, fs)
  end
  -- The single root that OWNS a module: the first (highest-priority) root that can
  -- locate it. A module and everything read on its behalf — source, manifest, and
  -- companion files — must come from this one root, or a vendored module could mix
  -- its Lua body with another root's (a different plugin/version) companion, which
  -- would break bundle reproducibility and the lockfile's per-module provenance.
  local function owner(name)
    for _, r in ipairs(resolvers) do
      if r.locate(name) then
        return r
      end
    end
    return nil
  end
  return {
    locate = function(name)
      local r = owner(name)
      return r and r.locate(name) or nil
    end,
    read = function(name)
      local r = owner(name)
      return r and r.read(name) or nil
    end,
    -- Read an arbitrary file relative to a root. When `name` is given, anchor to
    -- that module's owning root so its companions are read from the SAME root that
    -- supplied its source; without `name` (no owning module), fall back to the
    -- first root that has the file.
    read_raw = function(rel, name)
      if name then
        local r = owner(name)
        return r and r.read_raw(rel) or nil
      end
      for _, r in ipairs(resolvers) do
        local got = r.read_raw(rel)
        if got then
          return got
        end
      end
      return nil
    end,
    manifest = function(name)
      local r = owner(name)
      return r and r.manifest(name) or nil
    end,
  }
end

return M
