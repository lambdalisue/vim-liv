-- liv.std.process Neovim leaf: spawn (one-shot) via vim.system and open
-- (streaming) via vim.fn.jobstart. Output is captured as raw bytes (no text
-- conversion) so spawn is binary-safe; on_exit delivers {code, stdout, stderr}.
--
-- open() streams stdout/stderr line by line. jobstart's on_stdout does NOT hand
-- back clean lines: it yields a list split on "\n" where the first element
-- continues the previous chunk and the last element is a partial line (e.g.
-- `printf "a\nb\nc\n"` arrives as {"a","b","c",""}). We buffer a `pending`
-- fragment per stream, emit only completed lines, and flush a non-empty pending
-- on exit -- so a trailing newline emits nothing and a last line without a
-- newline is still delivered (matching the Vim 'nl' mode contract).
return function(_core)
  local M = {}

  ---@param cmd string[]
  ---@param on_done fun(result: liv.std.process.Result)
  ---@return fun() canceler
  function M.spawn(cmd, on_done)
    local handle = vim.system(cmd, {}, function(obj)
      on_done({
        code = obj.code,
        stdout = obj.stdout or "",
        stderr = obj.stderr or "",
      })
    end)
    return function()
      handle:kill(15) -- SIGTERM
    end
  end

  -- Build an on_stdout/on_stderr handler that re-assembles whole lines from
  -- jobstart's chunk-split list and invokes `emit(line)` once per line.
  local function liner(emit)
    local pending = ""
    return function(_id, data, _event)
      -- A pure exit signal arrives as {""}; nothing to do until real chunks.
      data[1] = pending .. data[1]
      pending = data[#data]
      for i = 1, #data - 1 do
        emit(data[i])
      end
    end, function()
      if pending ~= "" then
        emit(pending)
        pending = ""
      end
    end
  end

  ---@param cmd string[]
  ---@param opts liv.std.process.open_opts
  ---@return liv.std.process.handle
  function M.open(cmd, opts)
    local on_stdout, flush_out = liner(opts.on_stdout)
    local jobopts = { on_stdout = on_stdout }
    local flush_err
    if opts.on_stderr ~= nil then
      local on_stderr
      on_stderr, flush_err = liner(opts.on_stderr)
      jobopts.on_stderr = on_stderr
    end
    jobopts.on_exit = function(_id, code, _event)
      flush_out()
      if flush_err ~= nil then
        flush_err()
      end
      if opts.on_exit ~= nil then
        opts.on_exit({ code = code })
      end
    end

    local id = vim.fn.jobstart(cmd, jobopts)
    if id <= 0 then
      error("liv.std.process.open: failed to start command (jobstart returned " .. tostring(id) .. ")")
    end

    return {
      write = function(data)
        vim.fn.chansend(id, data)
      end,
      close = function()
        -- Signal EOF on the child's stdin so a stdin-reading child (e.g. cat)
        -- can finish; does not stop an already-running process.
        vim.fn.chanclose(id, "stdin")
      end,
      kill = function()
        vim.fn.jobstop(id)
      end,
    }
  end

  return M
end
