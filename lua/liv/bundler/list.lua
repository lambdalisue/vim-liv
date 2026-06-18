-- Bundler module listing (spec 0009): discover the bundle-able liv modules
-- present on a set of lua/ paths and tag each as already bundled or not. Used to
-- complete :LivAdd / :LivUpdate / :LivRemove. Pure Lua, editor-independent — the
-- caller enumerates the file paths (e.g. via the editor's globpath) and passes the
-- relative paths in.
local M = {}

-- Namespaces that are never vendored (dev tools), so never offered as bundle-able.
local DEV = { bundler = true, tester = true, generator = true }

-- A module is bundle-able when it is a runtime liv module: under `liv`, not a dev
-- tool, and no path segment is internal (a leading underscore — backends _nvim /
-- _vim, the dispatch _dispatch).
local function bundleable(mod)
  local segs = {}
  for s in mod:gmatch("[^.]+") do
    segs[#segs + 1] = s
  end
  if segs[1] ~= "liv" then
    return false
  end
  if DEV[segs[2] or ""] then
    return false
  end
  for _, s in ipairs(segs) do
    if s:sub(1, 1) == "_" then
      return false
    end
  end
  return true
end

-- Map lua file relpaths to bundle-able module names (deduped, sorted). A
-- `foo/init.lua` is the module `foo`; `foo.lua` is `foo`; `.deps.lua` manifests
-- and internal/dev files are skipped.
---@param relpaths string[] paths relative to a `lua/` root (e.g. "liv/std/buffer/init.lua")
---@return string[] modules
function M.discover(relpaths)
  local seen, out = {}, {}
  for _, rel in ipairs(relpaths) do
    if rel:match("%.lua$") and not rel:match("%.deps%.lua$") then
      local mod = rel:gsub("%.lua$", ""):gsub("/init$", ""):gsub("/", ".")
      if bundleable(mod) and not seen[mod] then
        seen[mod] = true
        out[#out + 1] = mod
      end
    end
  end
  table.sort(out)
  return out
end

-- Discovered modules tagged with whether each is already bundled.
---@param relpaths string[]
---@param bundled table<string, boolean> set of already-bundled module names
---@return { name: string, bundled: boolean }[]
function M.list(relpaths, bundled)
  bundled = bundled or {}
  local out = {}
  for _, name in ipairs(M.discover(relpaths)) do
    out[#out + 1] = { name = name, bundled = bundled[name] == true }
  end
  return out
end

return M
