-- liv.std.highlight Neovim backend: nvim_set_hl(0, name, def). The definition is
-- built from an explicit known-keys allowlist rather than forwarding the whole
-- attrs table, so unsupported keys (blink/dim) never reach the API. Colors are
-- normalized to "#rrggbb" (Neovim accepts ints or strings; normalizing keeps one
-- code path with the Vim backend).
return function(core)
  local set_hl = core.marshaled(vim.api.nvim_set_hl)

  -- Boolean highlight attributes Neovim exposes on nvim_set_hl.
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
    local def = {}
    if attrs.fg ~= nil then
      def.fg = color(attrs.fg)
    end
    if attrs.bg ~= nil then
      def.bg = color(attrs.bg)
    end
    if attrs.sp ~= nil then
      def.sp = color(attrs.sp)
    end
    for _, key in ipairs(ATTRS) do
      if attrs[key] then
        def[key] = true
      end
    end
    set_hl(0, name, core.dict(def))
  end

  return M
end
