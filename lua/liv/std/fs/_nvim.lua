-- liv.std.fs Neovim backend: native vim.uv.fs_* (preferred over vimscript).
-- Editor-dependent because stat/scandir route through the editor's native fs,
-- which differs observably from a pure-Lua impl (stock Lua has no portable stat
-- or directory listing): vim.uv reports type as "file"/"directory"/"link" and
-- mtime as {sec,nsec}. Use fs_lstat (NOT fs_stat) so a symlink reports "link"
-- instead of being silently followed — matching Vim's getftype and keeping the
-- type vocabulary aligned across editors. Map to liv's closed contract type set
-- ("file"/"dir"/"link", anything else "other"), and return nil for a missing
-- path (an absent value, not an operation failure).
-- The mutation/predicate primitives use vim.uv directly (native libuv): vim.uv
-- failures surface as (nil, message) tuples, which this backend converts into a
-- liv error() so an OPERATION FAILURE is pcall-able (an absent VALUE stays a
-- false/nil return). Predicates use fs_stat (NOT fs_lstat) so a symlink resolves
-- to its target's type — isdirectory()/filereadable() on Vim follow links too.
return function(_core)
  local TYPE = { file = "file", directory = "dir", link = "link" }

  -- 0755 / 0644 as numbers (Lua 5.1 has no octal literals).
  local MODE_DIR = tonumber("755", 8)

  local function fail(op, path, err)
    error("liv.std.fs." .. op .. ": " .. path .. ": " .. tostring(err), 3)
  end

  local M = {}

  ---@param path string
  ---@return liv.std.fs.Stat? stat nil if the path does not exist.
  function M.stat(path)
    local st = vim.uv.fs_lstat(path)
    if not st then
      return nil
    end
    return {
      size = st.size,
      mtime = st.mtime.sec,
      type = TYPE[st.type] or "other",
    }
  end

  ---@param path string
  ---@return boolean
  function M.exists(path)
    return vim.uv.fs_stat(path) ~= nil
  end

  ---@param path string
  ---@return boolean
  function M.is_dir(path)
    local st = vim.uv.fs_stat(path)
    return st ~= nil and st.type == "directory"
  end

  ---@param path string
  ---@return boolean
  function M.is_file(path)
    local st = vim.uv.fs_stat(path)
    return st ~= nil and st.type == "file"
  end

  -- Create one directory segment, tolerating EEXIST only when allowed (so the
  -- parents loop is idempotent like `mkdir -p`).
  local function mkdir_one(path, tolerate_exists)
    local ok, err, code = vim.uv.fs_mkdir(path, MODE_DIR)
    if not ok then
      if code == "EEXIST" and tolerate_exists then
        return
      end
      fail("mkdir", path, err)
    end
  end

  ---@param path string
  ---@param opts? { parents?: boolean }
  function M.mkdir(path, opts)
    if opts and opts.parents then
      -- Build each ancestor in turn; an already-present segment is fine.
      local prefix = path:sub(1, 1) == "/" and "/" or ""
      local acc = prefix
      for seg in path:gmatch("[^/]+") do
        acc = (acc == "" or acc == "/") and (acc .. seg) or (acc .. "/" .. seg)
        if not M.is_dir(acc) then
          mkdir_one(acc, true)
        end
      end
    else
      mkdir_one(path, false)
    end
  end

  -- Remove a single entry (file or empty directory). Raises on failure.
  ---@param path string
  ---@param is_directory boolean
  function M.remove_entry(path, is_directory)
    local ok, err
    if is_directory then
      ok, err = vim.uv.fs_rmdir(path)
    else
      ok, err = vim.uv.fs_unlink(path)
    end
    if not ok then
      fail("remove", path, err)
    end
  end

  ---@param src string
  ---@param dst string
  function M.rename(src, dst)
    local ok, err = vim.uv.fs_rename(src, dst)
    if not ok then
      fail("rename", src, err)
    end
  end

  ---@param path string
  function M.touch(path)
    if M.exists(path) then
      -- Bump mtime to now without altering content (libuv utime, seconds).
      local now = os.time()
      local ok, err = vim.uv.fs_utime(path, now, now)
      if not ok then
        fail("touch", path, err)
      end
      return
    end
    -- Create an empty file (O_WRONLY|O_CREAT, 0644).
    local fd, oerr = vim.uv.fs_open(path, "w", tonumber("644", 8))
    if not fd then
      fail("touch", path, oerr)
    end
    vim.uv.fs_close(fd)
  end

  ---@param path string
  ---@return string[]
  function M.scandir(path)
    local handle = vim.uv.fs_scandir(path)
    local names = {}
    if handle then
      while true do
        local name = vim.uv.fs_scandir_next(handle)
        if not name then
          break
        end
        names[#names + 1] = name
      end
    end
    return names
  end

  return M
end
