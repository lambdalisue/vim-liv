-- liv.std.autocmd Vim backend: define autocommands whose rhs calls the Lua
-- handler through the Vim 9 dispatch (the handler is held as a Funcref). The
-- context table is built in the rhs from <abuf>/<afile>/<amatch> and marshaled to
-- a plain Lua table by the dispatch boundary. trigger() fires a User event,
-- guarded so it stays silent when nothing listens (matching Neovim's
-- exec-autocmds).
--
-- Groups: Vim has no per-autocommand id, and `autocmd! {group} {event} {pat}`
-- removes EVERY autocommand in that group matching the event+pattern -- so two
-- subscriptions sharing one real augroup with the same event+pattern could not be
-- removed individually. To keep `sub.off()` per-subscription (the removal
-- contract, consistent with Neovim's id-based delete), each on() call gets its own
-- private augroup, prefixed by the caller's `group` for debuggability. `group` is
-- thus an organizational tag here; removal is always via the returned sub.
return function(core)
  local dispatch = require("liv.std._dispatch")(core)
  local seq = 0

  -- Built in the rhs and evaluated when the event fires; <abuf> is empty for
  -- non-buffer events, so str2nr("") yields 0.
  local CTX = "{'buf': str2nr(expand('<abuf>')), 'file': expand('<afile>'), 'match': expand('<amatch>')}"

  local M = {}

  ---@param events string|string[]
  ---@param opts? liv.std.autocmd.opts
  ---@param handler fun(ctx: liv.std.autocmd.ctx)
  ---@return liv.std.autocmd.sub
  function M.on(events, opts, handler)
    local id = dispatch.register(handler)
    local ev = type(events) == "table" and table.concat(events, ",") or events
    local pat
    if opts.buffer then
      -- Buffer-scoped autocommand: Vim's `<buffer=N>` pattern matches only events
      -- for that buffer (the cross-editor analogue of Neovim's buffer= option).
      pat = string.format("<buffer=%d>", opts.buffer)
    else
      pat = opts.pattern
      if type(pat) == "table" then
        pat = table.concat(pat, ",")
      end
      pat = pat or "*"
    end

    -- Each subscription gets its own private augroup so off() removes exactly it.
    seq = seq + 1
    local group = (opts.group or "liv_au") .. "_" .. seq

    local once = opts.once and " ++once" or ""
    core.cmd("augroup " .. group)
    core.cmd(string.format("autocmd %s %s%s %s", ev, pat, once, dispatch.invoke_rhs(id, CTX)))
    core.cmd("augroup END")

    local removed = false
    return {
      -- Idempotent: a second off() (or off() after a `once` autocommand removed
      -- itself) is a no-op. The private group is cleared and deleted wholesale, so
      -- sibling subscriptions (each in their own private group) are untouched.
      off = function()
        if removed then
          return
        end
        removed = true
        pcall(core.cmd, "autocmd! " .. group)
        pcall(core.cmd, "augroup! " .. group)
        dispatch.unregister(id)
      end,
    }
  end

  ---@param name string the User event name to fire
  function M.trigger(name)
    -- Fire when ANY User listener exists, not only one whose pattern is exactly
    -- `name`: a catch-all listener (`pattern = "*"`, registered as `#User#*`)
    -- must also receive the event, matching Neovim's exec_autocmds. The guard
    -- only avoids Vim's "No matching autocommands" message when nothing listens;
    -- a `<nomodeline>` keeps an unmatched fire side-effect-free.
    core.cmd(string.format("if exists('#User') | doautocmd <nomodeline> User %s | endif", name))
  end

  return M
end
