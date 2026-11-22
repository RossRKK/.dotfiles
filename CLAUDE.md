# Dotfiles

- Every nvim message, Lua errors and stack traces included, is logged to
  `~/.local/state/nvim/logs/messages-<YYYYMMDD-HHMMSS>-<pid>.log`, one file per
  nvim; read the newest one(s) when Ross reports nvim errors instead of asking
  him for `:messages`.
- Edits to this config must always be designed to work in WSL, native nixos and
  mac os. This is so that the consuming machines stay compatible
- Edits to this repo, and the related neovim plugins, should always be
  committed, merged to main and pushed. The lazy pins for plugins should be
  updated to ensure compatibility. This is so the latest version of the
  config and its dependencies are available to all machines
