-- Shared implementation for the path flavours (spec 0006).
--
-- A flavour is fully described by its separator set and whether drive paths
-- (C:\) count as absolute. `build` returns a complete, pure path API for one
-- flavour, so `posix` and `unc` are each deterministic and L1-testable on any
-- host; `init` picks the platform default at import.

-- cfg = { sep = output separator, sep_class = pattern class body of accepted
--         separators, drive = bool (treat C:\ as absolute) }
---@class liv.lua.path.Config
---@field sep string The output path separator.
---@field sep_class string Pattern class body of accepted separators.
---@field drive boolean Whether to treat drive paths (`C:\`) as absolute.

---Build a complete, pure path API for one flavour.
---@param cfg liv.lua.path.Config The flavour configuration.
---@return liv.lua.path.Flavour M The path API for this flavour.
return function(cfg)
  local SEP = cfg.sep
  local CLASS = cfg.sep_class
  local SEG = "[^" .. CLASS .. "]+"
  local LAST = "^.*()[" .. CLASS .. "]"
  local TRAIL = "[" .. CLASS .. "]+$"

  ---@class liv.lua.path.Flavour
  ---@field sep string The output path separator for this flavour.
  local M = { sep = SEP }

  local function is_sep(c)
    return c ~= "" and CLASS:find(c, 1, true) ~= nil
  end

  ---Report whether a path is absolute.
  ---@param p string The path to test.
  ---@return boolean is_abs `true` if `p` is absolute, `false` otherwise.
  function M.is_abs(p)
    if is_sep(p:sub(1, 1)) then
      return true
    end
    return cfg.drive and p:match("^%a:[/\\]") ~= nil
  end

  local function segments(p)
    local out = {}
    for seg in p:gmatch(SEG) do
      out[#out + 1] = seg
    end
    return out
  end

  ---Join path segments with this flavour's separator.
  ---@param ... string The path segments to join.
  ---@return string joined The joined path (`"."` when the result is empty).
  function M.join(...)
    local parts = { ... }
    local absolute = false
    local segs = {}
    for i = 1, select("#", ...) do
      local part = parts[i]
      if part ~= nil and part ~= "" then
        if i == 1 and is_sep(part:sub(1, 1)) then
          absolute = true
        end
        for _, seg in ipairs(segments(part)) do
          segs[#segs + 1] = seg
        end
      end
    end
    local joined = table.concat(segs, SEP)
    if absolute then
      return SEP .. joined
    end
    return joined == "" and "." or joined
  end

  ---Collapse `.`/`..` segments and redundant separators.
  ---@param p string The path to normalize.
  ---@return string normalized The normalized path (`"."` when the result is empty).
  function M.normalize(p)
    local absolute = is_sep(p:sub(1, 1))
    local stack = {}
    for _, seg in ipairs(segments(p)) do
      if seg == ".." then
        local top = stack[#stack]
        if top ~= nil and top ~= ".." then
          stack[#stack] = nil
        elseif not absolute then
          stack[#stack + 1] = ".."
        end
        -- on an absolute path, ".." at root is dropped
      elseif seg ~= "." then
        -- a "." segment is a no-op and is dropped
        stack[#stack + 1] = seg
      end
    end
    local joined = table.concat(stack, SEP)
    if absolute then
      return SEP .. joined
    end
    return joined == "" and "." or joined
  end

  local function strip_trailing(p)
    local stripped = (p:gsub(TRAIL, ""))
    if stripped == "" and #p > 0 then
      return SEP
    end
    return stripped
  end

  ---Return the directory portion of a path.
  ---@param p string The path to inspect.
  ---@return string dir The parent directory (`"."` when `p` has no directory).
  function M.dir(p)
    p = strip_trailing(p)
    if p == SEP then
      return SEP
    end
    local idx = p:match(LAST)
    if not idx then
      return "."
    end
    if idx == 1 then
      return SEP
    end
    return p:sub(1, idx - 1)
  end

  ---Return the final component of a path.
  ---@param p string The path to inspect.
  ---@return string base The last path component.
  function M.base(p)
    p = strip_trailing(p)
    if p == SEP then
      return SEP
    end
    return p:match(SEG .. "$") or p
  end

  ---Return the file extension of a path, including the leading dot.
  ---@param p string The path to inspect.
  ---@return string ext The extension (e.g. `".lua"`), or `""` when there is none.
  function M.ext(p)
    local name = M.base(p)
    local dot = name:match("^.+()%.")
    if not dot then
      return ""
    end
    return name:sub(dot)
  end

  return M
end
