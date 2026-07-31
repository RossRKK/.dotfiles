{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Single source of truth for where this repo is checked out.
  dotfilesDir = "${config.home.homeDirectory}/.dotfiles";

  # Symlink a path (relative to the repo root) into the Nix store's view.
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/${path}";
in
{
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      fish_vi_key_bindings
      any-nix-shell fish --info-right | source
    '';
  };

  programs.starship.enable = true;

  programs.zoxide = {
    enable = true;
    options = [ "--cmd cd" ];
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN = "1";
  };

  # Each key maps to `.config/<key>` in the repo.
  xdg.configFile =
    lib.genAttrs
      [
        "nvim"
        "lazygit"
        "starship.toml"
        "nix/nix.conf"
      ]
      (name: {
        source = link ".config/${name}";
      });

  # Each key is also its path relative to the repo root.
  home.file =
    lib.genAttrs
      [
        ".tmux.conf"
        ".local/bin/clipboard-copy"
      ]
      (path: {
        source = link path;
      });

  home.packages = with pkgs; [
    home-manager
    git
    lazygit
    gh
    tmux
    htop
    btop
    claude-code

    # Runtimes
    python3
    uv
    nodejs
    cargo
    rustc
    rustfmt
    rust-analyzer
    clippy

    # CLI tools
    any-nix-shell
    ripgrep
    fd
    imagemagick
    terraform

    # LSP servers (used by neovim via lspconfig; installed here so Mason doesn't
    # try to download pre-compiled binaries that won't run on NixOS)
    basedpyright
    typescript-language-server
    svelte-language-server
    lua-language-server
    yaml-language-server
    vscode-langservers-extracted # provides jsonls
    terraform-ls
    marksman
    helm-ls
    nixd

    # Debug adapters (nvim-dap; debugpy is not here because the python adapter
    # runs debugpy out of each project's venv, see dap.lua)
    vscode-js-debug # provides js-debug (pwa-node adapter)
    vscode-extensions.vadimcn.vscode-lldb.adapter # provides codelldb (used by rustaceanvim)

    # Formatters and CLI tools (same reason)
    gcc # tree-sitter CLI calls cc to compile parsers
    tree-sitter
    stylua
    prettierd
    ruff
    shfmt
    gdtoolkit_4 # provides gdformat / gdlint
    nixfmt # official nixfmt (RFC 166)
  ];
}
