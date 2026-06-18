-- liv.std.mark Neovim backend: extmarks in a private namespace. A line highlight
-- is line_hl_group; virtual text is a single end-of-line chunk; an intra-line
-- column span is a single extmark carrying hl_group with end_row/end_col. The
-- extmark id is returned directly; clear() drops the whole namespace for the
-- buffer.
return function(core)
  local has = require("liv.has")
  local create_ns = core.marshaled(vim.api.nvim_create_namespace)
  local set_extmark = core.marshaled(vim.api.nvim_buf_set_extmark)
  local del_extmark = core.marshaled(vim.api.nvim_buf_del_extmark)
  local clear_ns = core.marshaled(vim.api.nvim_buf_clear_namespace)
  local ns = create_ns("liv.std.mark")

  local M = {}

  ---@param buf integer
  ---@param line integer
  ---@param opts liv.std.mark.opts
  ---@return integer id
  function M.place(buf, line, opts)
    buf = buf or 0
    opts = opts or {}
    if opts.virt_text and not has("mark.virt_text") then
      error("liv.std.mark: virtual text is not available on this editor")
    end
    if opts.hl and not has("mark") then
      error("liv.std.mark: text marks are not available on this editor")
    end
    local o = {}
    if opts.hl then
      o.line_hl_group = opts.hl
    end
    if opts.virt_text then
      local group = opts.virt_text_hl or opts.hl
      o.virt_text = group and { { opts.virt_text, group } } or { { opts.virt_text } }
    end
    return set_extmark(buf, ns, line - 1, 0, core.dict(o))
  end

  ---@param buf integer
  ---@param from integer[] {line, col} 1-based, inclusive start
  ---@param to integer[] {line, col} 1-based, inclusive end
  ---@param opts liv.std.mark.range_opts
  ---@return integer id
  function M.range(buf, from, to, opts)
    buf = buf or 0
    opts = opts or {}
    if not has("mark.range") then
      error("liv.std.mark: range highlight is not available on this editor")
    end
    if not opts.hl then
      error("liv.std.mark: range requires opts.hl")
    end
    -- liv [col, end_col] is 1-based inclusive; the extmark end is 0-based
    -- exclusive, so start col-1 and end_col stays as the liv end column.
    return set_extmark(
      buf,
      ns,
      from[1] - 1,
      from[2] - 1,
      core.dict({ end_row = to[1] - 1, end_col = to[2], hl_group = opts.hl })
    )
  end

  ---@param buf integer
  ---@param id integer
  function M.remove(buf, id)
    del_extmark(buf or 0, ns, id)
  end

  ---@param buf integer
  function M.clear(buf)
    clear_ns(buf or 0, ns, 0, -1)
  end

  return M
end
