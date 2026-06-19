-- liv.std.highlight Vim backend: hlset([{...}]). The entry is built from an
-- explicit known-keys allowlist (unsupported blink/dim never reach hlset). Colors
-- are normalized to "#rrggbb" and set as guifg/guibg/guisp; the caller must
-- enable 'termguicolors' for GUI colors to render in a terminal. Boolean
-- attributes are mirrored into both `gui` and `cterm` dicts so they survive in
-- 256-color terminals as well.
return function(core)
  local hlset = core.marshaled(vim.fn.hlset)

  -- Boolean attributes Vim accepts in the gui/cterm attribute dicts.
  local ATTRS = {
    "bold",
    "italic",
    "underline",
    "undercurl",
    "reverse",
    "strikethrough",
  }

  ---@param c integer|string
  ---@return string
  local function color(c)
    if type(c) == "number" then
      return string.format("#%06x", c)
    end
    return c
  end

  local M = {}

  ---@param name string
  ---@param attrs liv.std.highlight.attrs
  function M.set(name, attrs)
    attrs = attrs or {}
    local entry = { name = name }
    if attrs.fg ~= nil then
      entry.guifg = color(attrs.fg)
    end
    if attrs.bg ~= nil then
      entry.guibg = color(attrs.bg)
    end
    if attrs.sp ~= nil then
      entry.guisp = color(attrs.sp)
    end
    local styles = {}
    local has_style = false
    for _, key in ipairs(ATTRS) do
      if attrs[key] then
        styles[key] = true
        has_style = true
      end
    end
    if has_style then
      entry.gui = core.dict(styles)
      -- A fresh dict per field: marshaling must not alias the same table twice.
      local cterm = {}
      for k, v in pairs(styles) do
        cterm[k] = v
      end
      entry.cterm = core.dict(cterm)
    end
    hlset(core.list({ core.dict(entry) }))
  end

  return M
end
