-- liv.std.cursor Neovim backend: drive the cursor through 'guicursor' + a
-- self-contained blended highlight. Neovim's TUI renders the cursor per the
-- 'guicursor' option, and a highlight with blend=100 makes the cell the cursor
-- occupies fully transparent — together they hide the cursor without depending on
-- the user's colorscheme.
--
-- hide() saves the current 'guicursor', defines a private "LivCursorHidden"
-- highlight (blend=100, reverse off), and points every mode group at a block
-- shape using that highlight. show() restores the saved 'guicursor'. The hidden
-- flag makes both verbs idempotent and prevents re-saving the already-hidden
-- value (which would corrupt the restore).
return function(core)
  local set_hl = core.marshaled(vim.api.nvim_set_hl)

  -- A private highlight name (not a colorscheme group) so hiding never depends on
  -- or clobbers the user's colors.
  local HIDDEN_HL = "LivCursorHidden"
  -- All cursor mode groups pointed at the blended highlight in block shape.
  local HIDDEN_GUICURSOR = "a:block-" .. HIDDEN_HL

  -- Quote a value as a Vim string literal (single-quoted; '' escapes a quote),
  -- so the saved 'guicursor' is restored verbatim through :let.
  local function vim_str(s)
    return "'" .. tostring(s):gsub("'", "''") .. "'"
  end

  -- saved holds the 'guicursor' captured at hide() time; hidden guards idempotency.
  local saved = nil
  local hidden = false

  local M = {}

  function M.hide()
    if hidden then
      return
    end
    saved = core.eval("&guicursor")
    -- blend=100 → fully transparent cell; reverse off so it does not paint the
    -- character under the cursor. Self-contained, colorscheme-independent.
    set_hl(0, HIDDEN_HL, core.dict({ blend = 100, reverse = false }))
    core.cmd("set guicursor=" .. HIDDEN_GUICURSOR)
    hidden = true
  end

  function M.show()
    if not hidden then
      return
    end
    core.cmd("let &guicursor = " .. vim_str(saved))
    saved = nil
    hidden = false
  end

  return M
end
