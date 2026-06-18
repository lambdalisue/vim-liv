-- liv.std.variable Vim backend: bind Vim builtins as marshaled function references
-- (vim.fn.*) — the same shape the _nvim backend uses for vim.api.*, so marshaling
-- stays in core and is never hand-rolled. Buffer/window/tab have scoped setters
-- (setbufvar/setwinvar/settabvar), but Vim has NO global-var setter function, so a
-- global set goes through `let g:x = json_decode(...)` -- json round-trips
-- arbitrary data (including v:true/v:null/empty containers).
--
-- Missing-value contract: an absent variable returns nil. Vim's getbufvar/
-- getwinvar/gettabvar otherwise default to "" for a missing key (indistinguishable
-- from a real empty string), so each is called with a unique sentinel default and
-- the sentinel is mapped back to nil. Global and v: have no such default form, so
-- they are guarded with exists() before reading.
local SENTINEL = "\1liv.std.variable:absent\1"
return function(core)
  local fn = vim.fn
  local bufnr = core.marshaled(fn.bufnr)
  local tabpagenr = core.marshaled(fn.tabpagenr)
  local getbufvar = core.marshaled(fn.getbufvar)
  local getwinvar = core.marshaled(fn.getwinvar)
  local gettabvar = core.marshaled(fn.gettabvar)
  local exists = core.marshaled(fn.exists)
  local json_encode = core.marshaled(fn.json_encode)
  local setbufvar = core.marshaled(fn.setbufvar)
  local setwinvar = core.marshaled(fn.setwinvar)
  local settabvar = core.marshaled(fn.settabvar)

  local M = { get = {}, set = {} }

  local function curbuf()
    return bufnr("%")
  end
  local function curtab()
    return tabpagenr()
  end

  local function absent_nil(value)
    if value == SENTINEL then
      return nil
    end
    return value
  end

  ---@param name string
  ---@return any
  M.get.global = function(name)
    if exists("g:" .. name) == 0 then
      return nil
    end
    return core.eval("g:" .. name)
  end
  ---@param name string
  ---@return any
  M.get.buffer = function(name)
    return absent_nil(getbufvar(curbuf(), name, SENTINEL))
  end
  ---@param name string
  ---@return any
  M.get.window = function(name)
    return absent_nil(getwinvar(0, name, SENTINEL)) -- 0 = current window
  end
  ---@param name string
  ---@return any
  M.get.tab = function(name)
    return absent_nil(gettabvar(curtab(), name, SENTINEL))
  end
  -- v: vars always exist as editor-defined slots; an unknown v: name does not,
  -- so guard with exists() and return nil for an undefined one.
  ---@param name string
  ---@return any
  M.get.vim = function(name)
    if exists("v:" .. name) == 0 then
      return nil
    end
    return core.eval("v:" .. name)
  end

  ---@param name string
  ---@param value any
  M.set.global = function(name, value)
    local json = json_encode(value)
    local literal = "'" .. json:gsub("'", "''") .. "'"
    core.cmd("let g:" .. name .. " = json_decode(" .. literal .. ")")
  end
  ---@param name string
  ---@param value any
  M.set.buffer = function(name, value)
    setbufvar(curbuf(), name, value)
  end
  ---@param name string
  ---@param value any
  M.set.window = function(name, value)
    setwinvar(0, name, value)
  end
  ---@param name string
  ---@param value any
  M.set.tab = function(name, value)
    settabvar(curtab(), name, value)
  end
  -- Vim has no setvvar; write through `let v:name = json_decode(...)`. A read-only
  -- v: var makes Vim raise here (an operation failure), which is acceptable.
  ---@param name string
  ---@param value any
  M.set.vim = function(name, value)
    local json = json_encode(value)
    local literal = "'" .. json:gsub("'", "''") .. "'"
    core.cmd("let v:" .. name .. " = json_decode(" .. literal .. ")")
  end

  return M
end
