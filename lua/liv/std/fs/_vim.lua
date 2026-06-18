-- liv.std.fs Vim backend: bind Vim builtins as marshaled function references
-- (vim.fn.*) — the same shape the _nvim backend uses for vim.api.*, so marshaling
-- stays in core and is never hand-rolled (Vim has no libuv). Editor-dependent
-- because stat/scandir route through the editor's native fs, which differs
-- observably from a pure-Lua impl (stock Lua has no portable stat or directory
-- listing). getftype reports "dir"/"file"/"link" but also "bdev"/"cdev"/"fifo"/
-- "socket"/"other" for special files (a different vocabulary from Neovim's), so
-- normalize anything outside {file,dir,link} to the shared "other"; for a missing
-- path getftype returns "" (and getfsize/getftime return -1), which we report as
-- nil (an absent value, not an operation failure).
return function(core)
  local fn = vim.fn
  local getfsize = core.marshaled(fn.getfsize)
  local getftime = core.marshaled(fn.getftime)
  local getftype = core.marshaled(fn.getftype)
  local readdir = core.marshaled(fn.readdir)

  local TYPE = { file = "file", dir = "dir", link = "link" }

  local M = {}

  ---@param path string
  ---@return liv.std.fs.Stat? stat nil if the path does not exist.
  function M.stat(path)
    local ftype = getftype(path)
    if ftype == "" then
      return nil
    end
    return {
      size = getfsize(path),
      mtime = getftime(path),
      type = TYPE[ftype] or "other",
    }
  end

  ---@param path string
  ---@return string[]
  function M.scandir(path)
    return readdir(path)
  end

  return M
end
