-- liv.std.cursor Vim backend: terminal Vim honours the 't_ve' (cursor visible) /
-- 't_vi' (cursor invisible) termcap strings. hide() saves 't_ve' and assigns the
-- 't_vi' string to it (so the next redraw emits the hide sequence); show()
-- restores the saved 't_ve'. The hidden flag makes both verbs idempotent and
-- prevents re-saving the already-hidden value (which would corrupt the restore).
--
-- Degradation: GUI Vim ignores termcap and renders the cursor per 'guicursor', so
-- there hide()/show() do not change the visible cursor. Under a headless harness
-- the terminal termcap is empty (&t_ve == &t_vi == ""), so hide() is observable
-- only as the relationship &t_ve == &t_vi, not as a value change.
return function(core)
  -- Quote a value as a Vim string literal (single-quoted; '' escapes a quote), so
  -- the termcap string (which may contain ESC bytes) round-trips through :let.
  local function vim_str(s)
    return "'" .. tostring(s):gsub("'", "''") .. "'"
  end

  -- saved holds the 't_ve' captured at hide() time; hidden guards idempotency.
  local saved = nil
  local hidden = false

  local M = {}

  function M.hide()
    if hidden then
      return
    end
    saved = core.eval("&t_ve")
    core.cmd("let &t_ve = " .. vim_str(core.eval("&t_vi")))
    hidden = true
  end

  function M.show()
    if not hidden then
      return
    end
    core.cmd("let &t_ve = " .. vim_str(saved))
    saved = nil
    hidden = false
  end

  return M
end
