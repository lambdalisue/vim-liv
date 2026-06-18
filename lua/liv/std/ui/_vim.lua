-- liv.std.ui Vim backend: popup_menu drives the selection (its callback receives
-- the 1-based index, or a non-positive value on cancel) and input() reads a line
-- (blocking, then the handler is invoked synchronously). notify echoes the message
-- with a level-appropriate highlight. The popup_menu callback is a plain Funcref,
-- so the Lua handler is passed directly — no string dispatch is needed here.
return function(core)
  local fn = vim.fn
  local popup_menu = core.marshaled(fn.popup_menu)
  -- inputdialog (not input) so cancel is distinguishable: bare input() returns ""
  -- on BOTH Esc and an empty Enter, but inputdialog's 3rd arg is returned on
  -- cancel, giving the handler a real nil on cancel (matching the Neovim backend).
  local inputdialog = core.marshaled(fn.inputdialog)

  -- A sentinel unlikely to be typed, used as inputdialog's cancelreturn.
  local CANCEL = "\27liv-prompt-cancel\27"

  local LEVELS = { info = "None", warn = "WarningMsg", error = "ErrorMsg" }

  -- Quote a value as a Vim string literal (single-quoted; '' escapes a quote).
  local function vim_str(s)
    return "'" .. tostring(s):gsub("'", "''") .. "'"
  end

  local M = {}

  ---@param items string[]
  ---@param opts { prompt?: string }
  ---@param handler fun(item: string?, index: integer?)
  function M.select(items, opts, handler)
    popup_menu(items, core.dict({
      title = opts.prompt,
      callback = function(_id, result)
        if result and result > 0 then
          handler(items[result], result)
        else
          handler(nil)
        end
      end,
    }))
  end

  ---@param opts { prompt?: string, default?: string }
  ---@param handler fun(text: string?)
  function M.prompt(opts, handler)
    local text = inputdialog(opts.prompt or "", opts.default or "", CANCEL)
    if text == CANCEL then
      handler(nil)
    else
      handler(text)
    end
  end

  ---@param msg string
  ---@param level? liv.std.ui.level
  function M.notify(msg, level)
    -- :echomsg (not execute("echomsg")) so the message lands in the history.
    core.cmd("echohl " .. (LEVELS[level or "info"] or "None"))
    core.cmd("echomsg " .. vim_str(msg))
    core.cmd("echohl None")
  end

  return M
end
