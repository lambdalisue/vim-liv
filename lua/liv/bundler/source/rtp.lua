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
---@return { locate: fun(name: string): string?, read: fun(name: string): string? }
function M.resolver(roots, fs)
  local resolvers = {}
  for _, root in ipairs(roots) do
    resolvers[#resolvers + 1] = path.resolver(root, fs)
  end
  local function first(method, name)
    for _, r in ipairs(resolvers) do
      local got = r[method](name)
      if got then
        return got
      end
    end
    return nil
  end
  return {
    locate = function(name)
      return first("locate", name)
    end,
    read = function(name)
      return first("read", name)
    end,
    read_raw = function(rel)
      return first("read_raw", rel)
    end,
    manifest = function(name)
      return first("manifest", name)
    end,
  }
end

return M
