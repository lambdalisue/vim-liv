-- Bundler `path` source resolver (spec 0008/0009): resolve modules from a source
-- `lua/` directory on disk. A module `liv.std.buffer` is the file
-- `<root>/liv/std/buffer.lua` or `<root>/liv/std/buffer/init.lua` (the plain file
-- wins). `locate` returns the path relative to `<root>` (so the vendorer can
-- mirror the same layout); `read` returns its contents.
--
-- Filesystem access is injected (`fs.exists(abspath)`, `fs.read(abspath)`) so the
-- resolver is L1-testable and can run standalone (io) or in the editor.
local M = {}

---@param root string the source `lua/` directory
---@param fs { exists: fun(path: string): boolean, read: fun(path: string): string? }
---@return { locate: fun(name: string): string?, read: fun(name: string): string? }
function M.resolver(root, fs)
  local function locate(name)
    local rel = name:gsub("%.", "/")
    for _, candidate in ipairs({ rel .. ".lua", rel .. "/init.lua" }) do
      if fs.exists(root .. "/" .. candidate) then
        return candidate
      end
    end
    return nil
  end

  return {
    locate = locate,
    read = function(name)
      local rel = locate(name)
      if not rel then
        return nil
      end
      return fs.read(root .. "/" .. rel)
    end,
  }
end

return M
