-- liv.bundler._iofs — the default filesystem for standalone vendoring
-- (bin/liv-bundler, no editor). exists/read use Lua io; write creates parent
-- directories and clean removes a subtree, both via the shell (POSIX). Inside the
-- editor, :LivBundle can inject a liv.std.fs-backed table instead; the bundler
-- itself only depends on the { exists, read, write, clean } interface.
local M = {}

function M.exists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

function M.read(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

local function shquote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

function M.write(path, content)
  local dir = path:match("^(.*)/[^/]+$")
  if dir then
    os.execute("mkdir -p " .. shquote(dir))
  end
  local f = assert(io.open(path, "wb"))
  f:write(content)
  f:close()
end

function M.clean(dir)
  os.execute("rm -rf " .. shquote(dir))
end

return M
