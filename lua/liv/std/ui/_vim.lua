-- liv.std.ui Vim backend: popup_menu drives the selection (its callback receives
-- the 1-based index, or a non-positive value on cancel) and input() reads a line
-- (blocking, then the handler is invoked synchronously). notify echoes the message
-- with a level-appropriate highlight. The popup_menu callback is a plain Funcref,
-- so the Lua handler is passed directly — no string dispatch is needed here.
return function(core)
  local dispatch = require("liv.std._dispatch")(core)
  local fn = vim.fn
  local popup_menu = core.marshaled(fn.popup_menu)
  -- inputdialog (not input) so cancel is distinguishable: bare input() returns ""
  -- on BOTH Esc and an empty Enter, but inputdialog's 3rd arg is returned on
  -- cancel, giving the handler a real nil on cancel (matching the Neovim backend).
  local inputdialog = core.marshaled(fn.inputdialog)
  -- input (not inputdialog) is the only Vim builtin that supports {completion},
  -- but it has no cancelreturn (its 3rd arg IS completion); inputdialog has
  -- cancelreturn but explicitly "Command-line completion is not supported". The
  -- two are mutually exclusive, so the completion path uses input() and forgoes
  -- the cancel sentinel (Esc yields "" there, not nil — see the completion branch).
  local input = core.marshaled(fn.input)

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
    popup_menu(
      items,
      core.dict({
        title = opts.prompt,
        callback = function(_id, result)
          if result and result > 0 then
            handler(items[result], result)
          else
            handler(nil)
          end
        end,
      })
    )
  end

  ---@param opts { prompt?: string, default?: string, completion?: fun(lead: string): string[] }
  ---@param handler fun(text: string?)
  function M.prompt(opts, handler)
    if opts.completion then
      -- Bind the Lua completion fn to a Vim-callable customlist function NAME via
      -- the dispatch (the same forwarder used for command-line completion). The
      -- customlist forwarder is called Func(ArgLead, CmdLine, CursorPos); adapt the
      -- author's fun(lead) to it (only the lead is contractually meaningful). Then
      -- run input() with the "customlist,<name>" completion form. input() carries
      -- no cancelreturn, so Esc yields "" here (NOT nil) — a documented degradation
      -- of the completion path; the non-completion path below keeps cancel->nil.
      local id, name = dispatch.register_complete(function(lead, _cmdline, _cursorpos)
        return opts.completion(lead)
      end)
      local ok, result = pcall(input, opts.prompt or "", opts.default or "", "customlist," .. name)
      dispatch.unregister(id) -- input() is blocking, so the binding is done now
      if not ok then
        error(result)
      end
      handler(result)
      return
    end
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
