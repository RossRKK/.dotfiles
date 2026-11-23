-- The nix build this nvim runs from: nvim-package.nix's info plugin, or nil when
-- lazy.nvim installs the plugins itself. A field, because require() turns a
-- module's own nil into true.
---@type { info: { plugins: { start: table<string, string>, lazy: table<string, string> }, settings: { config_directory: string }, progpath: string }|nil }
return { info = vim.g.nix_info_plugin_name and require(vim.g.nix_info_plugin_name) or nil }
