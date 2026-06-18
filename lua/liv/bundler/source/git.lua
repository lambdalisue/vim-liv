-- Bundler `git` source resolver (spec 0008/0009): vendor from a pinned git ref.
-- It clones `url` into a destination directory and (if given) checks out `ref`,
-- then resolves modules from `<dest>/lua` via the `path` resolver. The git
-- commands run through an injected `exec(cmd) -> ok` so this is L1-testable (record
-- the commands, fake success) and works standalone (os.execute) or in the editor.
local path = require("liv.bundler.source.path")

local M = {}

local function q(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Clone url into dest and check out ref. Returns dest on success, nil on failure.
---@param url string
---@param ref string? a branch/tag/sha (nil = default branch)
---@param dest string clone destination
---@param exec fun(cmd: string): boolean
---@return string? dest
function M.fetch(url, ref, dest, exec)
  exec("rm -rf " .. q(dest))
  if not exec("git clone --quiet " .. q(url) .. " " .. q(dest)) then
    return nil
  end
  if ref and ref ~= "" then
    if not exec("git -C " .. q(dest) .. " checkout --quiet " .. q(ref)) then
      return nil
    end
  end
  return dest
end

---@param url string
---@param ref string?
---@param dest string clone destination (e.g. a temp dir)
---@param fs { exists: fun(p): boolean, read: fun(p): string? }
---@param exec fun(cmd: string): boolean
---@return { locate: fun(name): string?, read: fun(name): string?, read_raw: fun(rel): string?, manifest: fun(name): table? }
function M.resolver(url, ref, dest, fs, exec)
  assert(M.fetch(url, ref, dest, exec), "liv.bundler: git fetch of " .. url .. " failed")
  return path.resolver(dest .. "/lua", fs)
end

return M
