-- liv.std.mark Vim backend: text properties. Each highlight group gets a lazily
-- registered prop type (highlight bound to the type). A line highlight is a
-- property spanning the line's bytes; virtual text is a property at column 0
-- (after the line) carrying `text`; an intra-line column span is a property
-- bounded by end_col. A multi-line range splits into one property per line that
-- all share the same liv id, so remove()/clear() sweep the whole span at once.
-- Vim has no per-mark id of its own, so liv assigns one and tracks each mark's
-- buffer and prop types, which also lets clear() remove exactly liv's marks (and
-- nobody else's) from a buffer.
return function(core)
  local fn = vim.fn
  local prop_type_add = core.marshaled(fn.prop_type_add)
  local bufnr = core.marshaled(fn.bufnr)
  local getbufline = core.marshaled(fn.getbufline)
  local prop_add = core.marshaled(fn.prop_add)
  local prop_remove = core.marshaled(fn.prop_remove)

  local has = require("liv.std.has")
  local seq = 0
  local marks = {} -- id -> { bufnr = integer, types = string[] }
  local registered = {} -- prop type name -> true

  local function ensure_type(name, group)
    if not registered[name] then
      prop_type_add(name, core.dict({ highlight = group }))
      registered[name] = true
    end
    return name
  end

  local function resolve(buf)
    if buf == nil or buf == 0 then
      return bufnr("")
    end
    return buf
  end

  local M = {}

  ---@param buf integer
  ---@param line integer
  ---@param opts liv.std.mark.opts
  ---@return integer id
  function M.place(buf, line, opts)
    opts = opts or {}
    if opts.virt_text and not has("mark.virt_text") then
      error("liv.std.mark: virtual text is not available on this editor")
    end
    if opts.hl and not has("mark") then
      error("liv.std.mark: text marks are not available on this editor")
    end
    local resolved = resolve(buf)
    seq = seq + 1
    local id = seq
    local types = {}
    if opts.hl then
      local t = ensure_type("liv_mark_hl_" .. opts.hl, opts.hl)
      local text = getbufline(resolved, line)[1] or ""
      prop_add(line, 1, core.dict({ bufnr = resolved, type = t, length = #text, id = id }))
      types[#types + 1] = t
    end
    if opts.virt_text then
      local group = opts.virt_text_hl or opts.hl or "Normal"
      local t = ensure_type("liv_mark_vt_" .. group, group)
      prop_add(line, 0, core.dict({ bufnr = resolved, type = t, text = opts.virt_text, id = id }))
      types[#types + 1] = t
    end
    marks[id] = { bufnr = resolved, types = types }
    return id
  end

  ---@param buf integer
  ---@param from integer[] {line, col} 1-based, inclusive start
  ---@param to integer[] {line, col} 1-based, inclusive end
  ---@param opts liv.std.mark.range_opts
  ---@return integer id
  function M.range(buf, from, to, opts)
    opts = opts or {}
    if not has("mark.range") then
      error("liv.std.mark: range highlight is not available on this editor")
    end
    if not opts.hl then
      error("liv.std.mark: range requires opts.hl")
    end
    local resolved = resolve(buf)
    seq = seq + 1
    local id = seq
    local t = ensure_type("liv_mark_range_" .. opts.hl, opts.hl)
    -- Each line of the span gets its own property sharing this id. liv end_col is
    -- 1-based inclusive; Vim's end_col is exclusive, hence +1. Interior lines run
    -- to one past the last byte; the final line stops at the requested end.
    for ln = from[1], to[1] do
      local start_col = (ln == from[1]) and from[2] or 1
      local end_col
      if ln == to[1] then
        end_col = to[2] + 1
      else
        local text = getbufline(resolved, ln)[1] or ""
        end_col = #text + 1
      end
      -- A zero-width span (e.g. start of an empty interior line) has nothing to
      -- color; Vim rejects such a property, so skip it.
      if end_col > start_col then
        prop_add(
          ln,
          start_col,
          core.dict({ bufnr = resolved, type = t, end_col = end_col, id = id })
        )
      end
    end
    marks[id] = { bufnr = resolved, types = { t } }
    return id
  end

  ---@param buf integer
  ---@param id integer
  function M.remove(_buf, id)
    local info = marks[id]
    if not info then
      return
    end
    for _, t in ipairs(info.types) do
      prop_remove(core.dict({ id = id, type = t, bufnr = info.bufnr, all = true }))
    end
    marks[id] = nil
  end

  ---@param buf integer
  function M.clear(buf)
    local resolved = resolve(buf)
    local ids = {}
    for id, info in pairs(marks) do
      if info.bufnr == resolved then
        ids[#ids + 1] = id
      end
    end
    for _, id in ipairs(ids) do
      M.remove(buf, id)
    end
  end

  return M
end
