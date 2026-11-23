-- The config directory this nvim runs: the nix build's own copy (or NVIM_CONFIG_DIR),
-- else ~/.config/nvim. stdpath("config") is always the live checkout, even under nix.
local nix_build = require("util.nix_build").info
return nix_build and nix_build.settings.config_directory or vim.fn.stdpath("config")
