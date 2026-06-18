-- Pinned editor versions the generated bindings target (à la denops'
-- supported_versions). The generator downloads each editor's
-- runtime/doc/options.txt (and later builtin.txt) at these tags, so the
-- generated, committed bindings are reproducible and version-accurate.
---@class liv.generator.SupportedVersions
---@field vim string Pinned Vim version tag.
---@field neovim string Pinned Neovim version tag.

---@type liv.generator.SupportedVersions
return {
  vim = "9.1.0000",
  neovim = "0.10.4",
}
