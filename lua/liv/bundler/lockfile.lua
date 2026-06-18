-- Bundler lockfile (spec 0008). Pure Lua, editor-independent.
--
-- Records the bundle so it can be reproduced, checked, updated, and removed
-- without re-specifying anything: a small `meta` header (plugin name, source kind,
-- where the source came from, and the explicit roots) followed by one record per
-- vendored module (its source kind, optional version, content hash). Serialization
-- is deterministic (meta in fixed order, modules sorted) so the same inputs yield
-- byte-identical lockfiles, and the hashes let a later run detect drift / diff.
local M = {}

local HEADER = "liv-lockfile 1"

-- A small, stable, non-cryptographic content hash (djb2). Each step stays within
-- the 2^53 exact-integer range, so it is identical on every Lua. Drift detection,
-- not security.
---@param content string
---@return string hash 8 hex digits
function M.hash(content)
  local h = 5381
  for i = 1, #content do
    h = (h * 33 + content:byte(i)) % 4294967296
  end
  return string.format("%08x", h)
end

-- lock = {
--   meta = { plugin?, source?, from?, ref?, roots?: string[] },
--   modules = { [name] = { source, version?, hash } },
-- }
---@param lock table
---@return string
function M.serialize(lock)
  local meta = lock.meta or {}
  local lines = { HEADER }
  local function put(k, v)
    if v ~= nil and v ~= "" then
      lines[#lines + 1] = "@" .. k .. "\t" .. v
    end
  end
  put("plugin", meta.plugin)
  put("source", meta.source)
  put("from", meta.from)
  put("ref", meta.ref)
  if meta.roots and #meta.roots > 0 then
    local roots = {}
    for _, r in ipairs(meta.roots) do
      roots[#roots + 1] = r
    end
    table.sort(roots)
    put("roots", table.concat(roots, ","))
  end
  lines[#lines + 1] = "" -- blank line separates meta from the module records

  local names = {}
  for name in pairs(lock.modules or {}) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local e = lock.modules[name]
    lines[#lines + 1] = table.concat({ name, e.source, e.version or "-", e.hash }, "\t")
  end
  return table.concat(lines, "\n") .. "\n"
end

---@param text string
---@return table lock
function M.parse(text)
  local lock = { meta = {}, modules = {} }
  local first = true
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if first then
      first = false -- the header line
    elseif line:sub(1, 1) == "@" then
      local k, v = line:match("^@([^\t]+)\t(.*)$")
      if k == "roots" then
        local roots = {}
        for r in v:gmatch("[^,]+") do
          roots[#roots + 1] = r
        end
        lock.meta.roots = roots
      elseif k then
        lock.meta[k] = v
      end
    elseif line ~= "" then
      local name, source, version, hash = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
      if name then
        lock.modules[name] = {
          source = source,
          version = version ~= "-" and version or nil,
          hash = hash,
        }
      end
    end
  end
  return lock
end

return M
