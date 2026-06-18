-- Bundler `path` source resolver (spec 0008/0009): resolve modules from a source
-- `lua/` directory on disk. A module `liv.std.buffer` is the file
-- `<root>/liv/std/buffer.lua` or `<root>/liv/std/buffer/init.lua` (the plain file
-- wins). `locate` returns the path relative to `<root>` (so the vendorer can
-- mirror the same layout); `read` returns its contents.
--
-- Filesystem access is injected (`fs.exists(abspath)`, `fs.read(abspath)`) so the
-- resolver is L1-testable and can run standalone (io) or in the editor. Besides a
-- module's source, the resolver can read an arbitrary file by its relative path
-- (`read_raw`, for companion files) and a module's dependency manifest
-- (`manifest`, the sibling `<module>.deps.lua`).
local M = {}

local load_chunk = loadstring or load -- 5.1 loadstring vs 5.2+ load

---@param root string the source `lua/` directory
---@param fs { exists: fun(path: string): boolean, read: fun(path: string): string? }
---@return { locate: fun(name): string?, read: fun(name): string?, read_raw: fun(rel): string?, manifest: fun(name): table? }
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

  local function read_raw(rel)
    return fs.read(root .. "/" .. rel)
  end

  return {
    locate = locate,
    read_raw = read_raw,
    read = function(name)
      local rel = locate(name)
      return rel and read_raw(rel) or nil
    end,
    -- The dependency manifest sits beside the module: foo.lua -> foo.deps.lua,
    -- bar/init.lua -> bar/init.deps.lua. It returns a Lua table { modules?, files? }.
    manifest = function(name)
      local rel = locate(name)
      if not rel then
        return nil
      end
      local src = read_raw((rel:gsub("%.lua$", ".deps.lua")))
      if not src then
        return nil
      end
      local chunk = load_chunk(src, "@deps")
      if not chunk then
        return nil
      end
      local ok, result = pcall(chunk)
      if ok and type(result) == "table" then
        return result
      end
      return nil
    end,
  }
end

return M
