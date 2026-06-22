-- liv.std.cursor Neovim backend: drive the cursor through 'guicursor' + a
-- self-contained transparent highlight. Neovim's TUI renders the cursor per the
-- 'guicursor' option, and a highlight carrying a gui attribute plus blend=100
-- makes the cell the cursor occupies fully transparent — together they hide the
-- cursor without depending on the user's colorscheme.
--
-- This mirrors vim-fern's proven recipe (autoload/fern/internal/cursor.vim), which
-- hides the cursor in terminals where a bare blend (no gui attribute), a *replaced*
-- 'guicursor', or no ColorScheme reapply did NOT:
--   * the highlight carries `gui=strikethrough blend=100` — a concrete gui attr, so
--     the blend is actually applied (a blend-only highlight can be ignored),
--   * hide() APPENDS `a:<hl>/lCursor` to 'guicursor' (keeping per-mode shapes),
--   * the highlight is REAPPLIED on ColorScheme (a colorscheme reload clears custom
--     highlights, which would otherwise resurrect the cursor).
--
-- hide() saves 'guicursor', defines the highlight (+ a once-wired ColorScheme
-- reapply), and appends the transparent entry. show() restores the saved
-- 'guicursor'. The hidden flag makes both verbs idempotent and prevents re-saving
-- the already-hidden value (which would corrupt the restore).
return function(core)
  local set_hl = core.marshaled(vim.api.nvim_set_hl)

  -- A private highlight name (not a colorscheme group) so hiding never depends on
  -- or clobbers the user's colors.
  local HIDDEN_HL = "LivCursorHidden"
  -- Appended to 'guicursor' on hide: the transparent highlight for every mode (and
  -- the language-mapping cursor), with no shape so per-mode shapes survive.
  local HIDDEN_ENTRY = "a:" .. HIDDEN_HL .. "/lCursor"

  -- Quote a value as a Vim string literal (single-quoted; '' escapes a quote), so
  -- the saved 'guicursor' is restored verbatim through :let.
  local function vim_str(s)
    return "'" .. tostring(s):gsub("'", "''") .. "'"
  end

  -- gui=strikethrough makes it a concrete highlight so blend=100 is honored; the
  -- blended cell is fully transparent, hiding the cursor. Colorscheme-independent.
  local function define_hl()
    set_hl(0, HIDDEN_HL, core.dict({ strikethrough = true, blend = 100 }))
  end

  -- saved holds the 'guicursor' captured at hide() time; hidden guards idempotency;
  -- reapply_wired ensures the ColorScheme reapply is registered only once.
  local saved = nil
  local hidden = false
  local reapply_wired = false

  -- Reapply the transparent highlight after any colorscheme reload (which clears
  -- custom highlights and would otherwise make the cursor reappear). Wired once.
  local function wire_reapply()
    if reapply_wired then
      return
    end
    reapply_wired = true
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("liv_cursor", { clear = true }),
      callback = define_hl,
    })
  end

  local M = {}

  function M.hide()
    if hidden then
      return
    end
    saved = core.eval("&guicursor")
    define_hl()
    wire_reapply()
    core.cmd("set guicursor+=" .. HIDDEN_ENTRY)
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
