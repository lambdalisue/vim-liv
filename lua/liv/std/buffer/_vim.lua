-- liv.std.buffer Vim backend: bind Vim builtins as marshaled function references
-- (vim.fn.*) — the same shape the _nvim backend uses for vim.api.*, so marshaling
-- stays in core and is never hand-rolled. Vim's builtins are already 1-based
-- inclusive, so ranges pass straight through. set_lines is not a mirror of lines:
-- it overwrites the overlap with setbufline, then appends the surplus or deletes
-- the shortfall. (Deleting a whole range first would hit Vim's "a buffer keeps
-- >=1 line" rule and leave a phantom empty line.) A handle of 0/nil resolves to
-- the current buffer number once, here in std.
return function(core)
  local fn = vim.fn
  local bufnr = core.marshaled(fn.bufnr)
  local getbufline = core.marshaled(fn.getbufline)
  local setbufline = core.marshaled(fn.setbufline)
  local appendbufline = core.marshaled(fn.appendbufline)
  local deletebufline = core.marshaled(fn.deletebufline)
  local getbufinfo = core.marshaled(fn.getbufinfo)
  local bufname = core.marshaled(fn.bufname)
  local bufexists = core.marshaled(fn.bufexists)
  local bufadd = core.marshaled(fn.bufadd)
  local bufload = core.marshaled(fn.bufload)
  local setbufvar = core.marshaled(fn.setbufvar)

  local M = {}

  -- Resolve 0/nil to the current buffer and validate an explicit handle, so an
  -- invalid buffer raises the SAME liv error on both editors. Vim's getbufline /
  -- bufname / setbufline silently return []/""/failure on an invalid buffer where
  -- Neovim's native API raises; this makes both fail loudly and identically.
  local function resolve(buf)
    if buf == nil or buf == 0 then
      return bufnr("%")
    end
    if bufexists(buf) ~= 1 then
      error("liv.std.buffer: invalid buffer id: " .. tostring(buf))
    end
    return buf
  end

  ---Get lines [first, last] (1-based inclusive) of a buffer.
  ---@param buf integer? buffer handle; 0/nil = current
  ---@param first integer first line (1-based, inclusive)
  ---@param last integer last line (1-based, inclusive)
  ---@return string[]
  function M.lines(buf, first, last)
    return getbufline(resolve(buf), first, last)
  end

  ---Replace lines [first, last] (1-based inclusive) of a buffer with xs.
  ---@param buf integer? buffer handle; 0/nil = current
  ---@param first integer first line (1-based, inclusive)
  ---@param last integer last line (1-based, inclusive)
  ---@param xs string[] replacement lines
  function M.set_lines(buf, first, last, xs)
    buf = resolve(buf)
    local old = last - first + 1
    if old < 0 then
      old = 0
    end
    local new = #xs
    local overwrite = old < new and old or new -- min(old, new)

    if overwrite > 0 then
      local head = {}
      for i = 1, overwrite do
        head[i] = xs[i]
      end
      setbufline(buf, first, core.list(head))
    end

    if new > old then
      local tail = {}
      for i = old + 1, new do
        tail[#tail + 1] = xs[i]
      end
      appendbufline(buf, first + old - 1, core.list(tail))
    elseif old > new then
      deletebufline(buf, first + new, last)
    end
  end

  ---Number of lines in a buffer.
  ---@param buf integer? buffer handle; 0/nil = current
  ---@return integer
  function M.count(buf)
    local info = getbufinfo(resolve(buf))
    return info[1].linecount
  end

  ---Name (path) of a buffer.
  ---@param buf integer? buffer handle; 0/nil = current
  ---@return string
  function M.name(buf)
    return bufname(resolve(buf))
  end

  ---Whether a buffer handle refers to a valid buffer. Must never raise (that is
  ---the whole point), so it does not go through the validating resolve().
  ---@param buf integer? buffer handle; 0/nil = current
  ---@return boolean
  function M.valid(buf)
    if buf == nil or buf == 0 then
      buf = bufnr("%")
    end
    return bufexists(buf) == 1
  end

  ---Create a buffer and return its handle. bufadd reuses an existing buffer of
  ---the given name (the reuse contract; empty name always creates a new buffer),
  ---so a named create returns the existing buffer's id when one exists — matching
  ---the Neovim backend's name-lookup-then-create.
  ---@param opts? { listed?: boolean, scratch?: boolean, name?: string }
  ---@return integer
  function M.create(opts)
    opts = opts or {}
    local buf = bufadd(opts.name or "") -- reuses an existing named buffer; empty = new
    bufload(buf)
    if opts.scratch then
      setbufvar(buf, "&buftype", "nofile")
      setbufvar(buf, "&bufhidden", "hide")
      setbufvar(buf, "&swapfile", 0)
    end
    setbufvar(buf, "&buflisted", opts.listed == false and 0 or 1)
    return buf
  end

  ---Wipe out (permanently remove) a buffer. Wiping an already-gone buffer is a
  ---no-op (the `silent!`), not an error, so it does not validate via resolve().
  ---@param buf integer? buffer handle; 0/nil = current
  function M.wipe(buf)
    if buf == nil or buf == 0 then
      buf = bufnr("%")
    end
    core.cmd("silent! bwipeout! " .. buf)
  end

  return M
end
