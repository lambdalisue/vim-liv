-- liv.has Vim backend: power features depend on Vim's compile-time features and
-- version, probed once via has(). Vim has no true-async filesystem (no libuv), so
-- "fs.async" is false; marks ride on text properties (Vim 9.0+), floats on the
-- popup window feature, and fetch on an external curl/wget being installed.
return function(core)
  local function has(feat)
    return core.eval("has('" .. feat .. "')") == 1
  end
  local function executable(cmd)
    return core.eval("executable('" .. cmd .. "')") == 1
  end

  local textprop = has("textprop")
  local popup = has("popupwin")

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
    ["fs.async"] = false,
    -- Streaming spawn rides on the job/channel API (Vim 8.0+ jobs, always
    -- present on a Vim that links Lua), with 'nl' line mode for per-line output.
    ["process.stream"] = has("job"),
    ["fetch"] = executable("curl") or executable("wget"),
  }

  ---@param feature liv.feature|string
  ---@return boolean
  return function(feature)
    return FEATURES[feature] == true
  end
end
