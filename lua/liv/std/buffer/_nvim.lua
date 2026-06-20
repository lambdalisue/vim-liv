-- liv.std.buffer Neovim backend: calls the native API directly (this file only
-- runs on Neovim), declaring marshaled bindings once via core.marshaled. Neovim
-- ranges are 0-based end-exclusive, so a 1-based inclusive [first,last] maps to
-- [first-1, last). A handle of 0/nil is the current buffer (native default).
return function(core)
  local get_lines = core.marshaled(vim.api.nvim_buf_get_lines)
  local set_lines = core.marshaled(vim.api.nvim_buf_set_lines)
  local line_count = core.marshaled(vim.api.nvim_buf_line_count)
  local get_name = core.marshaled(vim.api.nvim_buf_get_name)
  local set_name = core.marshaled(vim.api.nvim_buf_set_name)
  local is_valid = core.marshaled(vim.api.nvim_buf_is_valid)
  local create_buf = core.marshaled(vim.api.nvim_create_buf)
  local buf_delete = core.marshaled(vim.api.nvim_buf_delete)
  local find_buf = core.marshaled(vim.fn.bufnr)
  local escape = core.marshaled(vim.fn.escape)

  local M = {}

  -- Resolve 0/nil to the current buffer and validate an explicit handle, so an
  -- invalid buffer raises the SAME liv error as the Vim backend (instead of the
  -- native nvim message), keeping the failure identical across editors.
  local function resolve(buf)
    if buf == nil or buf == 0 then
      return 0
    end
    if not is_valid(buf) then
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
    return get_lines(resolve(buf), first - 1, last, false)
  end

  ---Replace lines [first, last] (1-based inclusive) of a buffer with xs.
  ---@param buf integer? buffer handle; 0/nil = current
  ---@param first integer first line (1-based, inclusive)
  ---@param last integer last line (1-based, inclusive)
  ---@param xs string[] replacement lines
  function M.set_lines(buf, first, last, xs)
    set_lines(resolve(buf), first - 1, last, false, xs)
  end

  ---Number of lines in a buffer.
  ---@param buf integer? buffer handle; 0/nil = current
  ---@return integer
  function M.count(buf)
    return line_count(resolve(buf))
  end

  ---Name (path) of a buffer.
  ---@param buf integer? buffer handle; 0/nil = current
  ---@return string
  function M.name(buf)
    return get_name(resolve(buf))
  end

  ---Whether a buffer handle refers to a valid buffer.
  ---@param buf integer? buffer handle; 0/nil = current
  ---@return boolean
  function M.valid(buf)
    return is_valid(buf or 0)
  end

  ---Create a buffer and return its handle. If `opts.name` is given and a buffer of
  ---that name already exists, that existing buffer's id is RETURNED (reuse) instead
  ---of raising; otherwise a new buffer is created and named. (The native
  ---nvim_buf_set_name raises E95 on a name clash; this looks the name up first so
  ---both editors honor the same reuse contract.)
  ---@param opts? { listed?: boolean, scratch?: boolean, name?: string }
  ---@return integer
  function M.create(opts)
    opts = opts or {}
    if opts.name and opts.name ~= "" then
      -- Exact, anchored, magic-escaped lookup so it matches only this name (not a
      -- partial) and survives the editor's path canonicalization (/tmp ->
      -- /private/tmp); bufnr returns -1 when no such buffer exists.
      local pattern = "^" .. escape(opts.name, "\\.*$[~^") .. "$"
      local existing = find_buf(pattern)
      if existing ~= -1 then
        return existing
      end
    end
    local buf = create_buf(opts.listed ~= false, opts.scratch == true)
    if opts.name then
      set_name(buf, opts.name)
    end
    return buf
  end

  ---Wipe out (permanently remove) a buffer. Wiping an already-gone buffer is a
  ---no-op (matches the Vim backend's `silent! bwipeout!`), not an error.
  ---@param buf integer? buffer handle; 0/nil = current
  function M.wipe(buf)
    pcall(buf_delete, buf or 0, core.dict({ force = true }))
  end

  -- Resolve 0/nil to a concrete buffer id for the buffer-local option index
  -- (vim.bo[0] would target the *current* buffer rather than a stable id, which
  -- is wrong once we have changed it; resolve up front).
  local current_buf = vim.api.nvim_get_current_buf

  ---Run fn with buf as the current buffer, then restore the previously-current
  ---buffer, even if fn errors. Returns fn's value.
  ---
  ---nvim_buf_call already runs the callback with buf current and restores the
  ---prior buffer afterward (including on error), so this is a thin native pass —
  ---no manual save/restore needed.
  ---
  ---The callback is NOT routed through core.marshaled: the boundary here is
  ---Lua↔Lua (a plain Lua callback and its plain Lua return), not an editor-value
  ---boundary, so marshaling would mangle a returned table. The _nvim backend is
  ---allowed to call vim.api directly; this is that case.
  ---@generic T
  ---@param buf integer? buffer handle; 0/nil = current
  ---@param fn fun(): T
  ---@return T
  function M.with(buf, fn)
    return vim.api.nvim_buf_call(resolve(buf), fn)
  end

  ---Run fn with buf's 'modifiable' temporarily enabled (and 'readonly' cleared),
  ---restoring both options afterward even if fn errors. Returns fn's value. This
  ---is the "edit a normally-read-only buffer" pattern. Uses vim.bo[buf] because
  ---nvim_buf_set_option is deprecated on recent Neovim; options are scalars, so
  ---no marshaling is involved.
  ---@generic T
  ---@param buf integer? buffer handle; 0/nil = current
  ---@param fn fun(): T
  ---@return T
  function M.modifiable(buf, fn)
    local id = resolve(buf)
    if id == 0 then
      id = current_buf()
    end
    local bo = vim.bo[id]
    local saved_modifiable = bo.modifiable
    local saved_readonly = bo.readonly
    bo.modifiable = true
    bo.readonly = false
    local ok, result = pcall(fn)
    bo.modifiable = saved_modifiable
    bo.readonly = saved_readonly
    if not ok then
      error(result, 0) -- re-raise without re-prefixing the position
    end
    return result
  end

  return M
end
