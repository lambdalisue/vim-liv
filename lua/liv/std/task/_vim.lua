-- liv.std.task Vim leaves: bind Vim timer builtins as marshaled function
-- references (vim.fn.*) — the same shape the _nvim backend uses for vim.api.*, so
-- marshaling stays in core and is never hand-rolled. A Lua function passed to
-- timer_start is auto-converted to a Funcref (which holds the Lua reference
-- alive), so the callback fires normally; Vim invokes it with the timer id, which
-- the wrappers ignore. wait pumps the loop with :sleep, which processes timers in
-- headless (-es) too.
return function(core)
  local fn = vim.fn
  local timer_start = core.marshaled(fn.timer_start)
  local timer_stop = core.marshaled(fn.timer_stop)

  local M = {}

  -- Vim fires same-delay timers in REVERSE creation order (LIFO), unlike Neovim's
  -- FIFO vim.schedule. To keep async ordering identical across editors, queue the
  -- callbacks and drain them FIFO from a single timer per tick. (Callbacks
  -- scheduled during a drain land in the next tick's queue, preserving order.)
  local queue = {}
  local draining = false

  ---@param fn fun()
  function M.schedule(fn)
    queue[#queue + 1] = fn
    if not draining then
      draining = true
      timer_start(0, function()
        draining = false
        local batch = queue
        queue = {}
        for i = 1, #batch do
          batch[i]()
        end
      end)
    end
  end

  ---@param ms integer
  ---@param fn fun()
  ---@return fun() canceler
  function M.timer(ms, fn)
    local id = timer_start(ms, function()
      fn()
    end)
    return function()
      timer_stop(id)
    end
  end

  -- Pump the event loop until cond() or ms elapses; returns whether cond() held.
  ---@param ms integer
  ---@param cond fun(): boolean
  ---@return boolean
  function M.wait(ms, cond)
    local elapsed = 0
    while not cond() and elapsed < ms do
      core.cmd("sleep 10m")
      elapsed = elapsed + 10
    end
    return cond()
  end

  return M
end
