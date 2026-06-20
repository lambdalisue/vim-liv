-- liv.std.option Vim backend: bind Vim builtins as marshaled function references
-- (vim.fn.*) — the same shape the _nvim backend uses for vim.api.*, so marshaling
-- stays in core and is never hand-rolled. The option seam still uses core.eval/cmd
-- for `&name` reads and `let &...` writes. Vim returns boolean options as 0/1 (the
-- init layer normalizes those to Lua booleans using the boolean-name set); on set,
-- the value is formatted by its OWN Lua type (boolean -> 1/0, string -> quoted,
-- number -> raw), so no declared option type is needed. Buffer/window-local
-- options use setbufvar/setwinvar with '&name' and accept an optional target
-- handle (buf number / window id), defaulting to current; global/local use
-- `let &g:name = expr` / `let &l:name = expr` with the formatted value.
return function(core)
  local fn = vim.fn
  local bufnr = core.marshaled(fn.bufnr)
  local getbufvar = core.marshaled(fn.getbufvar)
  local getwinvar = core.marshaled(fn.getwinvar)
  local setbufvar = core.marshaled(fn.setbufvar)
  local setwinvar = core.marshaled(fn.setwinvar)

  local function curbuf()
    return bufnr("%")
  end

  -- A nil/0 buffer target resolves to the current buffer number; a nil/0 window
  -- target resolves to 0 (getwinvar/setwinvar treat 0 as the current window).
  local function buf_target(target)
    if target == nil or target == 0 then
      return curbuf()
    end
    return target
  end
  local function win_target(target)
    if target == nil or target == 0 then
      return 0
    end
    return target
  end

  local M = {}

  function M.get(scope, name, target)
    if scope == "b" then
      return getbufvar(buf_target(target), "&" .. name)
    elseif scope == "w" then
      return getwinvar(win_target(target), "&" .. name)
    end
    local sigil = (scope == "g" and "g:") or (scope == "l" and "l:") or ""
    return core.eval("&" .. sigil .. name)
  end

  function M.set(scope, name, value, target)
    -- Format by the value's OWN Lua type: a boolean option is set with true/false
    -- (-> 1/0), a string option with a string, a number option with a number.
    if type(value) == "boolean" then
      value = value and 1 or 0
    end
    if scope == "b" then
      setbufvar(buf_target(target), "&" .. name, value)
      return
    elseif scope == "w" then
      setwinvar(win_target(target), "&" .. name, value)
      return
    end
    local sigil = scope == "g" and "g:" or "l:"
    local expr
    if type(value) == "string" then
      expr = "'" .. value:gsub("'", "''") .. "'"
    else
      expr = tostring(value)
    end
    core.cmd("let &" .. sigil .. name .. " = " .. expr)
  end

  -- Reset to default. `g` resets the global default (`setglobal name&`, matching
  -- `&g:name`); `b`/`w`/`l` reset the current-buffer/window local default
  -- (`setlocal name&`, matching the local value those scopes read).
  function M.reset(scope, name)
    if scope == "g" then
      core.cmd("setglobal " .. name .. "&")
    else
      core.cmd("setlocal " .. name .. "&")
    end
  end

  return M
end
