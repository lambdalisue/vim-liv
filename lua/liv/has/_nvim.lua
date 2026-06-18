-- liv.has Neovim backend: the in-contract editor features are natively available
-- on Neovim (extmarks, floats, libuv), so those are a flat set of trues. fetch is
-- the exception — it needs an external curl/wget — so it is probed once.
return function(core)
  local executable = core.marshaled(vim.fn.executable)
  local FEATURES = {
    ["async"] = true,
    ["popup"] = true,
    ["popup.border"] = true,
    ["mark"] = true,
    ["mark.virt_text"] = true,
    ["mark.range"] = true,
    ["highlight"] = true,
    ["fs.async"] = true,
    ["process.stream"] = true,
    ["fetch"] = (executable("curl") == 1 or executable("wget") == 1),
  }
  ---@param feature liv.feature|string
  ---@return boolean
  return function(feature)
    return FEATURES[feature] == true
  end
end
