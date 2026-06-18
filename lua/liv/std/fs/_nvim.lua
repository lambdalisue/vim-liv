-- liv.std.fs Neovim backend: native vim.uv.fs_* (preferred over vimscript).
-- Editor-dependent because stat/scandir route through the editor's native fs,
-- which differs observably from a pure-Lua impl (stock Lua has no portable stat
-- or directory listing): vim.uv reports type as "file"/"directory"/"link" and
-- mtime as {sec,nsec}. Use fs_lstat (NOT fs_stat) so a symlink reports "link"
-- instead of being silently followed — matching Vim's getftype and keeping the
-- type vocabulary aligned across editors. Map to liv's closed contract type set
-- ("file"/"dir"/"link", anything else "other"), and return nil for a missing
-- path (an absent value, not an operation failure).
return function(_core)
  local TYPE = { file = "file", directory = "dir", link = "link" }

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
