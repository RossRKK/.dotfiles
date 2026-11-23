-- The nix build this nvim runs from (nvim-package.nix), read from its info
-- plugin; nil when lazy.nvim installs the plugins itself. A field, because
-- require() turns a module's own nil into true.

---@class nix_build.Build
---@field plugin_dirs table<string, string> each plugin, by the name lazy.nvim gives it, to its directory
---@field config_dir string the config this nvim runs (the build's, or NVIM_CONFIG_DIR)
---@field nvim string this build's nvim, to start another like it

local info = vim.g.nix_info_plugin_name and require(vim.g.nix_info_plugin_name) or nil

---@type { build: nix_build.Build|nil }
return {
  build = info and {
    plugin_dirs = info.info.plugin_dirs,
    config_dir = info.settings.config_directory,
    nvim = info.progpath,
  } or nil,
}
