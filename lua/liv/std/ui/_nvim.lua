-- liv.std.ui Neovim backend: the native, user-overridable Lua hooks vim.ui.select
-- / vim.ui.input (so a user's configured selector/input UI is respected) and
-- vim.notify. These are pure-Lua hooks consuming plain Lua values — no editor
-- boundary is crossed — so they are called directly (no core.marshaling). They
-- are looked up at call time, not captured, so a test/user override is honored.
return function(_core)
  local LEVELS = {
    info = vim.log.levels.INFO,
    warn = vim.log.levels.WARN,
    error = vim.log.levels.ERROR,
  }

  local M = {}

  ---@param items string[]
  ---@param opts { prompt?: string }
  ---@param handler fun(item: string?, index: integer?)
  function M.select(items, opts, handler)
    opts = opts or {}
    vim.ui.select(items, { prompt = opts.prompt }, function(item, index)
      handler(item, index)
    end)
  end

  ---@param opts { prompt?: string, default?: string }
  ---@param handler fun(text: string?)
  function M.prompt(opts, handler)
    opts = opts or {}
    vim.ui.input({ prompt = opts.prompt, default = opts.default }, function(text)
      handler(text)
    end)
  end

  ---@param msg string
  ---@param level? liv.std.ui.level
  function M.notify(msg, level)
    vim.notify(msg, LEVELS[level or "info"] or LEVELS.info)
  end

  return M
end
