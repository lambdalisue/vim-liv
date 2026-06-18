-- liv.std.option Vim backend: bind Vim builtins as marshaled function references
-- (vim.fn.*) — the same shape the _nvim backend uses for vim.api.*, so marshaling
-- stays in core and is never hand-rolled. The option seam still uses core.eval/cmd
-- for `&name` reads and `let &...` writes. Vim returns boolean options as 0/1 (the
-- init layer normalizes those to Lua booleans using the option type); on set,
-- booleans are written as 1/0. Buffer/window-local options use setbufvar/setwinvar
-- with '&name' and accept an optional target handle (buf number / window id),
-- defaulting to current; global/local use `let &g:name = expr` / `let &l:name =
-- expr` with a type-formatted value.
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

  function M.set(scope, name, value, type_, target)
    if type_ == "boolean" then
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
    if type_ == "string" then
      expr = "'" .. tostring(value):gsub("'", "''") .. "'"
    else
      expr = tostring(value)
    end
    core.cmd("let &" .. sigil .. name .. " = " .. expr)
  end

  return M
end
