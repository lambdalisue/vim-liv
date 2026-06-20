-- Bundler migration notices (spec 0008) — vitalizer's headline feature, ported.
-- On update, surface ONLY the breaking-change entries that (a) fall in the version
-- range being crossed and (b) affect a module the plugin actually bundles. Pure
-- Lua, editor-independent, L1-testable: it parses MIGRATIONS.md text and filters;
-- the cli decides old/new versions and prints/confirms.
--
-- MIGRATIONS.md entry format (the file may also hold a markdown header, prose, and
-- a fenced example, all ignored):
--   2.0.0
--       Modules: std.buffer, std.window
--       lines() ranges are now 1-based inclusive (was 0-based).
local M = {}

-- Compare two dotted versions numerically. Returns -1 / 0 / 1.
---@param a string
---@param b string
---@return integer
function M.compare(a, b)
  local function parts(v)
    local t = {}
    for p in v:gmatch("[^.]+") do
      t[#t + 1] = tonumber(p) or 0
    end
    return t
  end
  local pa, pb = parts(a), parts(b)
  local n = math.max(#pa, #pb)
  for i = 1, n do
    local x, y = pa[i] or 0, pb[i] or 0
    if x < y then
      return -1
    elseif x > y then
      return 1
    end
  end
  return 0
end

-- Parse MIGRATIONS.md text into entries. A version line is a non-indented line
-- starting with a digit (so the markdown header/prose are skipped); fenced code
-- blocks (```...```) are skipped entirely so the format example is not parsed.
---@param text string
---@return { version: string, modules: string[]|"*", description: string }[]
function M.parse(text)
  local entries = {}
  local current
  local in_fence = false
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if line:match("^```") then
      in_fence = not in_fence
    elseif not in_fence then
      if line:match("^%d") then
        current = { version = line:match("^(%S+)"), modules = {}, _desc = {} }
        entries[#entries + 1] = current
      elseif current then
        local mods = line:match("^%s+Modules:%s*(.+)$")
        if mods then
          if mods:match("^%*%s*$") then
            current.modules = "*"
          else
            for mod in mods:gmatch("[^,%s]+") do
              current.modules[#current.modules + 1] = mod
            end
          end
        else
          local desc = line:match("^%s+(.-)%s*$")
          if desc and desc ~= "" then
            current._desc[#current._desc + 1] = desc
          end
        end
      end
    end
  end
  for _, e in ipairs(entries) do
    e.description = table.concat(e._desc, " ")
    e._desc = nil
  end
  return entries
end

-- Does an entry's module list affect any bundled module? "*" matches all; a short
-- name like "std.buffer" matches the bundled "liv.std.buffer" (suffix on a dot
-- boundary) as well as an exact full name.
local function affects(entry_modules, bundled)
  if entry_modules == "*" then
    return true
  end
  for _, name in ipairs(entry_modules) do
    for b in pairs(bundled) do
      if b == name or b:sub(-(#name + 1)) == "." .. name then
        return true
      end
    end
  end
  return false
end

-- Entries newer than `from` and at most `to`, affecting a bundled module, oldest
-- first. `from`/`to` are versions; `bundled` is a set { [module name] = true }.
---@param entries table[]
---@param from string
---@param to string
---@param bundled table<string, boolean>
---@return table[] relevant
function M.relevant(entries, from, to, bundled)
  local out = {}
  for _, e in ipairs(entries) do
    if
      M.compare(e.version, from) > 0
      and M.compare(e.version, to) <= 0
      and affects(e.modules, bundled)
    then
      out[#out + 1] = e
    end
  end
  table.sort(out, function(x, y)
    return M.compare(x.version, y.version) < 0
  end)
  return out
end

return M
