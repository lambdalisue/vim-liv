-- liv.std.option Neovim backend: native nvim_*_option_value, which already
-- returns/accepts correctly-typed values (boolean for boolean options), so no
-- normalization is needed here. Scope keys: g global, b buffer, w window, l local.
-- The buffer/window scopes accept an optional target handle (buf/win); when
-- omitted they target the current buffer/window. The invariant opts dicts (global,
-- local, current buf/win) are built once at import; only a non-current target
-- builds a fresh dict per call.
return function(core)
  local get_opt = core.marshaled(vim.api.nvim_get_option_value)
  local set_opt = core.marshaled(vim.api.nvim_set_option_value)

  -- Invariant option-target dicts, hoisted once (no per-call allocation).
  local opt_global = core.dict({ scope = "global" })
  local opt_local = core.dict({ scope = "local" })
  local opt_curbuf = core.dict({ buf = 0 })
  local opt_curwin = core.dict({ win = 0 })

  -- Resolve a scope + optional target to the option-target dict. Only a
  -- non-current buffer/window target needs a fresh dict.
  local function target_dict(scope, target)
    if scope == "g" then
      return opt_global
    elseif scope == "l" then
      return opt_local
    elseif scope == "b" then
      if target == nil or target == 0 then
        return opt_curbuf
      end
      return core.dict({ buf = target })
    else -- "w"
      if target == nil or target == 0 then
        return opt_curwin
      end
      return core.dict({ win = target })
    end
  end

  local M = {}

  function M.get(scope, name, target)
    return get_opt(name, target_dict(scope, target))
  end

  function M.set(scope, name, value, target)
    set_opt(name, value, target_dict(scope, target))
  end

  -- Reset to default via the editor Ex command (no native "reset" exists in
  -- nvim_set_option_value). `g` resets the global default (`setglobal name&`),
  -- the others the current-buffer/window local default (`setlocal name&`) — each
  -- matching the value the same scope's get reads.
  function M.reset(scope, name)
    if scope == "g" then
      core.cmd("setglobal " .. name .. "&")
    else
      core.cmd("setlocal " .. name .. "&")
    end
  end

  return M
end
