-- liv.std.has Neovim backend: the in-contract editor features are natively available
-- on Neovim (extmarks, floats, libuv), so those are a flat set of trues. fetch is
-- the exception — it needs an external curl/wget — so it is probed once.
return function(core)
  local executable = core.marshaled(vim.fn.executable)
  local has_curl = executable("curl") == 1
  local FEATURES = {
    ["async"] = true,
    ["popup"] = true,
    ["popup.border"] = true,
    ["mark"] = true,
    ["mark.virt_text"] = true,
    ["mark.range"] = true,
    ["highlight"] = true,
    ["cursor.hide"] = true,
    ["fs.async"] = true,
    ["process.stream"] = true,
    ["fetch"] = (has_curl or executable("wget") == 1),
    -- Multipart form upload needs curl; wget has no clean multipart support.
    ["fetch.form"] = has_curl,
  }
  ---@param feature liv.feature|string
  ---@return boolean
  return function(feature)
    return FEATURES[feature] == true
  end
end
