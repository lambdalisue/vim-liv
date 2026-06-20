-- liv.std.fs — filesystem access (spec 0006/0007).
--
-- Synchronous and binary-safe by default. read/write use stock Lua io in binary
-- mode (identical on both editors, no editor needed for the bytes). stat/scandir
-- need the editor (stock Lua has no portable stat or directory listing) and are
-- backend-selected: Neovim uses the native vim.uv.fs_* (preferred), Vim uses the
-- vimscript builtins getfsize/getftime/getftype/readdir. True async fs is not
-- worth it on Vim (no libuv); it is opt-in later, reusing liv.std.process, and
-- gated by liv.std.has("fs.async").
local core = require("liv.core")
local pathlib = require("liv.lua.path")

local backend = (core.is_nvim and require("liv.std.fs._nvim") or require("liv.std.fs._vim"))(core)

-- File metadata returned by stat. type is a closed set: "file"/"dir"/"link", or
-- "other" for anything else (special files) so both editors agree.
---@class liv.std.fs.Stat
---@field size integer File size in bytes.
---@field mtime integer Last-modified time (seconds since the Unix epoch).
---@field type string Entry type: "file"/"dir"/"link"/"other".

-- Reserved options for read/write. Currently accepted but ignored (read/write are
-- synchronous and binary-safe). `async` opts into true async fs once supported,
-- gated by liv.std.has("fs.async") — Neovim libuv only (Vim is sync, see spec 0007).
---@class liv.std.fs.IOOpts
---@field async? boolean Reserved: opt into true async I/O (liv.std.has("fs.async")).

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

-- List the entries (names, not full paths) directly under `p`.
---@param p string Directory to list.
---@return string[] entries Entry names (not full paths) directly under `p`.
function M.scandir(p)
  return backend.scandir(p)
end

-- Report whether anything exists at `p` (a file, directory, or other entry).
-- A missing path is an absent VALUE, so this returns false (never errors).
---@param p string Path to test.
---@return boolean exists
function M.exists(p)
  return backend.exists(p)
end

-- Report whether `p` is a directory (symlinks are followed to their target).
---@param p string Path to test.
---@return boolean is_dir
function M.is_dir(p)
  return backend.is_dir(p)
end

-- Report whether `p` is a regular file (symlinks are followed to their target).
---@param p string Path to test.
---@return boolean is_file
function M.is_file(p)
  return backend.is_file(p)
end

-- Options for mkdir.
---@class liv.std.fs.MkdirOpts
---@field parents? boolean Create intermediate directories (mkdir -p). When true,
---  an already-existing directory is success; when false, it is an error.

-- Create the directory `p`. Raises (pcall-able) on failure. With
-- `opts.parents` (default false), intermediate directories are created and an
-- existing target is treated as success (mkdir -p semantics); without it, a
-- missing intermediate or an existing target raises.
---@param p string Directory to create.
---@param opts? liv.std.fs.MkdirOpts
function M.mkdir(p, opts)
  backend.mkdir(p, opts)
end

-- Options for remove.
---@class liv.std.fs.RemoveOpts
---@field recursive? boolean Remove a directory tree (rm -rf). When true, a
---  missing path is a no-op success; when false, a missing path is an error.

-- Remove the file or directory `p`. Raises (pcall-able) on failure. Without
-- `opts.recursive`, `p` must be an existing file or empty directory and a
-- missing path raises (rm semantics). With `opts.recursive`, a directory tree
-- is removed depth-first and a missing path is a no-op success (rm -rf).
---@param p string Path to remove.
---@param opts? liv.std.fs.RemoveOpts
function M.remove(p, opts)
  local recursive = opts and opts.recursive or false
  if not M.exists(p) then
    if recursive then
      return -- rm -rf on a missing path is a no-op success.
    end
    error("liv.std.fs.remove: " .. p .. ": no such path", 2)
  end
  if recursive and M.is_dir(p) then
    -- Depth-first: remove every descendant before the directory itself.
    local entries = M.walk(p, { hidden = true })
    table.sort(entries, function(a, b)
      return #a > #b -- longer paths are deeper; remove them first
    end)
    for _, entry in ipairs(entries) do
      backend.remove_entry(entry, M.is_dir(entry))
    end
    backend.remove_entry(p, true)
  else
    backend.remove_entry(p, M.is_dir(p))
  end
end

-- Options for copy.
---@class liv.std.fs.CopyOpts
---@field recursive? boolean Copy a directory tree (cp -r).

-- Copy `src` to `dst`. Raises (pcall-able) on failure. A single file is copied
-- binary-safe via read/write. With `opts.recursive`, a directory tree is copied,
-- recreating its structure under `dst`.
---@param src string Source path.
---@param dst string Destination path.
---@param opts? liv.std.fs.CopyOpts
function M.copy(src, dst, opts)
  local recursive = opts and opts.recursive or false
  if recursive and M.is_dir(src) then
    M.mkdir(dst, { parents = true })
    for _, name in ipairs(M.scandir(src)) do
      M.copy(pathlib.join(src, name), pathlib.join(dst, name), opts)
    end
  else
    M.write(dst, M.read(src))
  end
end

-- Move/rename `src` to `dst`. Raises (pcall-able) on failure.
---@param src string Source path.
---@param dst string Destination path.
function M.rename(src, dst)
  backend.rename(src, dst)
end

-- Create the empty file `p` if it is absent, otherwise update its mtime to now
-- without altering its content. Raises (pcall-able) on failure.
---@param p string Path to touch.
function M.touch(p)
  backend.touch(p)
end

-- Return a fresh, unique temporary path under the editor's temp directory (so it
-- honors the editor's temp settings). The path does not yet exist on disk.
---@return string path A unique temporary path.
function M.tempname()
  return core.call("tempname")
end

-- Expand `~` and environment-variable references in `p` using the editor's
-- expand() builtin (e.g. "~/.config", "$HOME/x"). Editor-dependent.
---@param p string Path with `~`/`$ENV` references.
---@return string expanded
function M.expand(p)
  return core.call("expand", p)
end

-- Options for find_upward.
---@class liv.std.fs.FindUpwardOpts
---@field from? string Directory to start the upward search from (default: cwd).

-- Search the directory tree UPWARD from `opts.from` (default cwd) for an entry
-- named `name`, returning its full path or nil when no ancestor holds it. Useful
-- for locating project roots (e.g. ".git", "package.json"). A not-found result
-- is an absent VALUE, so it returns nil (never errors).
---@param name string Basename to look for at each level.
---@param opts? liv.std.fs.FindUpwardOpts
---@return string? found Full path to the entry, or nil when not found.
function M.find_upward(name, opts)
  local dir = (opts and opts.from) or core.call("getcwd")
  while true do
    local candidate = pathlib.join(dir, name)
    if M.exists(candidate) then
      return candidate
    end
    local parent = pathlib.dir(dir)
    if parent == dir then
      return nil -- reached the filesystem root (fixpoint)
    end
    dir = parent
  end
end

-- Options for walk.
---@class liv.std.fs.WalkOpts
---@field depth? integer Maximum recursion depth (default: unlimited). depth=1
---  lists only the immediate children (like scandir, but full paths).
---@field hidden? boolean Include dotfile entries (default: false).
---@field type? string Keep only "file" or "dir" entries (default: all). Note:
---  directories are still traversed even when filtered from the results.
---@field pattern? string|fun(name: string): boolean Keep only entries whose
---  basename matches a Lua pattern, or for which the predicate returns true.

-- Recursively list the tree under `p`, returning full paths. See
-- liv.std.fs.WalkOpts for filters. Synchronous; an async variant is not provided
-- (it would be gated by liv.std.has("fs.async"); Neovim libuv only).
---@param p string Directory to walk.
---@param opts? liv.std.fs.WalkOpts
---@return string[] paths Full paths of the matching entries.
function M.walk(p, opts)
  opts = opts or {}
  local max_depth = opts.depth
  local hidden = opts.hidden or false
  local want_type = opts.type
  local pattern = opts.pattern

  local function keep(name, is_directory)
    if not hidden and name:sub(1, 1) == "." then
      return false
    end
    if want_type == "file" and is_directory then
      return false
    end
    if want_type == "dir" and not is_directory then
      return false
    end
    if type(pattern) == "function" then
      return pattern(name) and true or false
    elseif type(pattern) == "string" then
      return name:match(pattern) ~= nil
    end
    return true
  end

  local results = {}
  local function recurse(current, depth)
    for _, name in ipairs(M.scandir(current)) do
      local full = pathlib.join(current, name)
      local is_directory = M.is_dir(full)
      local visible = hidden or name:sub(1, 1) ~= "."
      if keep(name, is_directory) then
        results[#results + 1] = full
      end
      -- Traverse into visible subdirectories even when the type filter would
      -- exclude them from the results (filtering output is not pruning).
      if is_directory and visible and (max_depth == nil or depth < max_depth) then
        recurse(full, depth + 1)
      end
    end
  end
  recurse(p, 1)
  return results
end

return M
