-- liv.std.process Vim leaf: spawn (one-shot) and open (streaming) via job_start.
-- The callbacks are Lua functions assigned as dict fields, which Vim
-- auto-converts to Funcrefs holding the Lua reference alive (the §6.1 callback
-- wiring; a dict *constructor* does not convert them, so field assignment is
-- required, and the dict must be a real vim.dict -- core.dict only *tags* a Lua
-- table and would not produce Funcrefs).
--
-- spawn captures output in 'raw' mode for binary safety. open streams stdout
-- (and optionally stderr) in 'nl' mode, which already delivers one whole line
-- per callback (trailing newline stripped) -- so no chunk re-assembly is needed
-- here, unlike the Neovim leaf. JSONL/line data is NUL-free, so 'nl' is safe.
--
-- Streaming needs a live job handle for write/close/kill, but Vim's if_lua
-- cannot represent a job/channel value (vim.call("job_start",...) returns nil to
-- Lua), so the job lives entirely in the Vim 9 companion (_vim.vim): it is held
-- by a numeric id, and write/close/kill drive it through that id via core.call,
-- which marshals data/args as real arguments (never interpolated into a command
-- string). The exit_cb dispatches to Lua and then drops the registry entry.
return function(core)
  local M = {}

  -- Source the companion once (it guards re-sourcing); it sits beside this file.
  local here = debug.getinfo(1, "S").source:sub(2) -- strip the leading '@'
  core.cmd("source " .. here:gsub("%.lua$", ".vim"))

  ---@param cmd string[]
  ---@param spawn_opts liv.std.process.spawn_opts?
  ---@param on_done fun(result: liv.std.process.Result)
  ---@return fun() canceler
  function M.spawn(cmd, spawn_opts, on_done)
    spawn_opts = spawn_opts or {}
    local out, err = {}, {}
    local opts = vim.dict({ out_mode = "raw", err_mode = "raw" })
    if spawn_opts.cwd ~= nil then
      opts.cwd = spawn_opts.cwd
    end
    if spawn_opts.env ~= nil then
      -- env EXTENDS the parent environment: Vim's job_start {env} adds these on
      -- top of the inherited variables.
      opts.env = vim.dict(spawn_opts.env)
    end
    opts.out_cb = function(_ch, msg)
      out[#out + 1] = msg
    end
    opts.err_cb = function(_ch, msg)
      err[#err + 1] = msg
    end
    opts.exit_cb = function(_job, status)
      on_done({
        code = status,
        stdout = table.concat(out),
        stderr = table.concat(err),
      })
    end
    local job = vim.call("job_start", vim.list(cmd), opts)
    return function()
      vim.call("job_stop", job)
    end
  end

  ---@param cmd string[]
  ---@param opts liv.std.process.open_opts
  ---@return liv.std.process.handle
  function M.open(cmd, opts)
    -- Pass each callback as a real argument (a Lua function -> Vim Funcref), or
    -- NIL when absent so the companion's type() check skips it. The Lua callbacks
    -- take Vim's native callback signatures -- out_cb/err_cb get (channel, msg),
    -- exit gets (status) -- because the companion assigns them directly as job
    -- options (a vim9 lambda wrapping a Lua Funcref fails to compile). The
    -- companion drops the registry entry in its own (vimscript) exit handler;
    -- the Lua exit_cb must NOT call back into vimscript, since Vim rejects a
    -- re-entrant call() from inside a channel callback.
    local out_cb = function(_ch, msg)
      opts.on_stdout(msg)
    end
    local err_cb = core.NIL
    if opts.on_stderr ~= nil then
      err_cb = function(_ch, msg)
        opts.on_stderr(msg)
      end
    end
    local exit_cb = core.NIL
    if opts.on_exit ~= nil then
      exit_cb = function(status)
        opts.on_exit({ code = status })
      end
    end

    -- cwd/env cross as real marshaled args (NIL when absent so the companion's
    -- type() guard skips them); env EXTENDS the parent environment.
    local cwd = opts.cwd ~= nil and opts.cwd or core.NIL
    local env = opts.env ~= nil and core.dict(opts.env) or core.NIL

    local id = core.call("LivProcStart", cmd, out_cb, err_cb, exit_cb, cwd, env)

    local function kill()
      core.call("LivProcStop", id)
    end
    return {
      write = function(data)
        core.call("LivProcSend", id, data)
      end,
      close = function()
        -- Close the child's stdin so a stdin-reading child (e.g. cat) sees EOF
        -- and can finish; does not stop an already-running process.
        core.call("LivProcCloseIn", id)
      end,
      kill = kill,
      stop = kill, -- alias
    }
  end

  return M
end
