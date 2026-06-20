-- liv.std.has Vim backend: power features depend on Vim's compile-time features and
-- version, probed once via has(). Vim has no true-async filesystem (no libuv), so
-- "fs.async" is false; marks ride on text properties (Vim 9.0+), floats on the
-- popup window feature, and fetch on an external curl/wget being installed.
return function(core)
  -- Bind the builtins as marshaled references (the same pattern the _nvim backend
  -- and every other _vim backend use), rather than building an eval string per
  -- probe: marshaling stays in core and there is no string-interpolation seam.
  local vim_has = core.marshaled(vim.fn.has)
  local vim_executable = core.marshaled(vim.fn.executable)
  local function has(feat)
    return vim_has(feat) == 1
  end
  local function executable(cmd)
    return vim_executable(cmd) == 1
  end

  local textprop = has("textprop")
  local popup = has("popupwin")
  local has_curl = executable("curl")

  local FEATURES = {
    ["async"] = true,
    ["popup"] = popup,
    ["popup.border"] = popup,
    ["mark"] = textprop,
    -- Text-property virtual text (the `text` argument) landed in Vim 9.0.
    ["mark.virt_text"] = textprop and has("patch-9.0.0"),
    -- Intra-line column-range highlight rides on text-property end_col.
    ["mark.range"] = textprop,
    -- Named highlight groups via hlset() are always present on a Vim that links
    -- Lua (the function landed long before Lua support).
    ["highlight"] = true,
    -- Terminal Vim hides/shows via t_ve/t_vi; GUI Vim degrades (uses guicursor).
    ["cursor.hide"] = true,
    ["fs.async"] = false,
    -- Streaming spawn rides on the job/channel API (Vim 8.0+ jobs, always
    -- present on a Vim that links Lua), with 'nl' line mode for per-line output.
    ["process.stream"] = has("job"),
    ["fetch"] = has_curl or executable("wget"),
    -- Multipart form upload needs curl; wget has no clean multipart support.
    ["fetch.form"] = has_curl,
  }

  ---@param feature liv.feature|string
  ---@return boolean
  return function(feature)
    return FEATURES[feature] == true
  end
end
