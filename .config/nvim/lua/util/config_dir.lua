-- The config directory this nvim runs: the nix build's own copy (or NVIM_CONFIG_DIR),
-- else ~/.config/nvim. stdpath("config") is always the live checkout, even under nix.
local build = require("util.nix_build").build
return build and build.config_dir or vim.fn.stdpath("config")
