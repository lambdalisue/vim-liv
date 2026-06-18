-- liv.std.fs — filesystem access (spec 0006/0007).
--
-- Synchronous and binary-safe by default. read/write use stock Lua io in binary
-- mode (identical on both editors, no editor needed for the bytes). stat/scandir
-- need the editor (stock Lua has no portable stat or directory listing) and are
-- backend-selected: Neovim uses the native vim.uv.fs_* (preferred), Vim uses the
-- vimscript builtins getfsize/getftime/getftype/readdir. True async fs is not
-- worth it on Vim (no libuv); it is opt-in later, reusing liv.std.process, and
-- gated by liv.has("fs.async").
local core = require("liv.core")

local backend = (core.is_nvim and require("liv.std.fs._nvim") or require("liv.std.fs._vim"))(core)

-- File metadata returned by stat. type is a closed set: "file"/"dir"/"link", or
-- "other" for anything else (special files) so both editors agree.
---@class liv.std.fs.Stat
---@field size integer File size in bytes.
---@field mtime integer Last-modified time (seconds since the Unix epoch).
---@field type string Entry type: "file"/"dir"/"link"/"other".

-- Reserved options for read/write. Currently accepted but ignored (read/write are
-- synchronous and binary-safe). `async` opts into true async fs once supported,
-- gated by liv.has("fs.async") — Neovim libuv only (Vim is sync, see spec 0007).
---@class liv.std.fs.IOOpts
---@field async? boolean Reserved: opt into true async I/O (liv.has("fs.async")).

local M = {}

-- Read the whole file as a binary-safe byte string. Errors (pcall-able) if the
-- file cannot be opened. `opts` is reserved (see liv.std.fs.IOOpts); the current
-- behavior is always synchronous.
---@param path string Path to the file.
---@param opts? liv.std.fs.IOOpts Reserved options (currently ignored).
---@return string data The whole file as a binary-safe byte string.
function M.read(path, opts)
  local _ = opts -- reserved; read is synchronous for now
  local f, err = io.open(path, "rb")
  if not f then
    error("liv.std.fs.read: " .. tostring(err), 2)
  end
  local data = f:read("*a")
  f:close()
  return data
end

-- Write `data` (a byte string) to `path`, replacing it. Binary-safe. `opts` is
-- reserved (see liv.std.fs.IOOpts); the current behavior is always synchronous.
---@param path string Path to the file.
---@param data string Byte string to write.
---@param opts? liv.std.fs.IOOpts Reserved options (currently ignored).
function M.write(path, data, opts)
  local _ = opts -- reserved; write is synchronous for now
  local f, err = io.open(path, "wb")
  if not f then
    error("liv.std.fs.write: " .. tostring(err), 2)
  end
  f:write(data)
  f:close()
end

-- File metadata: { size, mtime, type }. Returns nil for a nonexistent path (an
-- absent value, not an operation failure). type is "file"/"dir"/"link"/"other".
---@param path string Path to inspect.
---@return liv.std.fs.Stat? stat File metadata, or nil if the path does not exist.
function M.stat(path)
  return backend.stat(path)
end

-- List the entries (names, not full paths) directly under `path`.
---@param path string Directory to list.
---@return string[] entries Entry names (not full paths) directly under `path`.
function M.scandir(path)
  return backend.scandir(path)
end

return M
