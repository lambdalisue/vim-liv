-- Bundler lockfile (spec 0008). Pure Lua, editor-independent.
--
-- Records, per vendored module, its source kind (path/rtp/git/luarock), an
-- optional version (git sha or semver), and a content hash. Serialization is
-- deterministic (sorted by module name) so the same inputs produce byte-identical
-- lockfiles, and the recorded hashes let a later bundle detect drift / drive
-- add/update/remove. The format is a tiny line-based one (a header line, then one
-- tab-separated record per module) — easy to diff in review.
local M = {}

local HEADER = "liv-lockfile 1"

-- A small, stable, non-cryptographic content hash (djb2). Each step stays within
-- the 2^53 exact-integer range, so it is identical on every Lua. For drift
-- detection, not security.
---@param content string
---@return string hash 8 hex digits
function M.hash(content)
  local h = 5381
  for i = 1, #content do
    h = (h * 33 + content:byte(i)) % 4294967296
  end
  return string.format("%08x", h)
end

-- lock = { modules = { [name] = { source=string, version=string?, hash=string } } }
---@param lock { modules: table<string, { source: string, version?: string, hash: string }> }
---@return string
function M.serialize(lock)
  local names = {}
  for name in pairs(lock.modules) do
    names[#names + 1] = name
  end
  table.sort(names)
  local lines = { HEADER }
  for _, name in ipairs(names) do
    local e = lock.modules[name]
    lines[#lines + 1] = table.concat({ name, e.source, e.version or "-", e.hash }, "\t")
  end
  return table.concat(lines, "\n") .. "\n"
end

---@param text string
---@return { modules: table<string, { source: string, version?: string, hash: string }> }
function M.parse(text)
  local lock = { modules = {} }
  local first = true
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if line ~= "" then
      if first then
        first = false -- skip the header line
      else
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
  end
  return lock
end

return M
