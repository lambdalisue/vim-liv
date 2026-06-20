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
-- The mutation primitives bind Vim builtins that report failure by RETURN CODE
-- rather than raising: mkdir()/rename()/writefile() return 0 on failure, delete()
-- returns -1. This backend inspects the marshaled return and error()s itself, so
-- an OPERATION FAILURE is pcall-able. Predicates use isdirectory()/filereadable()
-- (which follow symlinks) rather than the lstat-based stat(), so a symlink-to-dir
-- reports is_dir true — matching the Neovim fs_stat path.
return function(core)
  local fn = vim.fn
  local getfsize = core.marshaled(fn.getfsize)
  local getftime = core.marshaled(fn.getftime)
  local getftype = core.marshaled(fn.getftype)
  local readdir = core.marshaled(fn.readdir)
  local isdirectory = core.marshaled(fn.isdirectory)
  local filereadable = core.marshaled(fn.filereadable)
  local raw_mkdir = core.marshaled(fn.mkdir)
  local raw_delete = core.marshaled(fn.delete)
  local raw_rename = core.marshaled(fn.rename)
  local readfile = core.marshaled(fn.readfile)
  local writefile = core.marshaled(fn.writefile)

  local TYPE = { file = "file", dir = "dir", link = "link" }

  local function fail(op, path, detail)
    error("liv.std.fs." .. op .. ": " .. path .. ": " .. detail, 3)
  end

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

  ---@param path string
  ---@return boolean
  function M.exists(path)
    return filereadable(path) == 1 or isdirectory(path) == 1
  end

  ---@param path string
  ---@return boolean
  function M.is_dir(path)
    return isdirectory(path) == 1
  end

  ---@param path string
  ---@return boolean
  function M.is_file(path)
    -- A regular file: readable but not a directory.
    return filereadable(path) == 1 and isdirectory(path) == 0
  end

  ---@param path string
  ---@param opts? { parents?: boolean }
  function M.mkdir(path, opts)
    local parents = opts and opts.parents or false
    if M.is_dir(path) then
      if parents then
        return -- mkdir -p: an existing directory is success.
      end
      fail("mkdir", path, "directory already exists")
    end
    -- mkdir('p') also creates intermediates; '' is a single level.
    local ok = raw_mkdir(path, parents and "p" or "")
    if ok ~= 1 then
      fail("mkdir", path, "mkdir() failed")
    end
  end

  -- Remove a single entry (file or empty directory). Raises on failure.
  -- Vim's delete() needs the 'd' flag to remove a directory (an empty one); a
  -- bare delete() only removes files.
  ---@param path string
  ---@param is_directory boolean
  function M.remove_entry(path, is_directory)
    if raw_delete(path, is_directory and "d" or "") ~= 0 then
      fail("remove", path, "delete() failed")
    end
  end

  ---@param src string
  ---@param dst string
  function M.rename(src, dst)
    if raw_rename(src, dst) ~= 0 then
      fail("rename", src, "rename() failed")
    end
  end

  ---@param path string
  function M.touch(path)
    if M.exists(path) then
      -- Re-stamp mtime without altering content: rewrite the existing bytes via
      -- writefile (Vim has no utime builtin). readfile/writefile with 'b' keeps
      -- it binary-safe; an empty file round-trips as an empty list.
      local lines = readfile(path, "b")
      if writefile(lines, path, "b") ~= 0 then
        fail("touch", path, "writefile() failed")
      end
      return
    end
    -- Create an empty file: an empty list with the 'b' flag writes zero bytes.
    if writefile(core.list({}), path, "b") ~= 0 then
      fail("touch", path, "writefile() failed")
    end
  end

  return M
end
