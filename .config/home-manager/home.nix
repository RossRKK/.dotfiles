{ config, pkgs, ... }:

{
  home.username = "rossrkk";
  home.homeDirectory = "/home/rossrkk";
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    git
    fish
    starship
    ghostty
    nerd-fonts._0xproto
    zoxide
    tmux
    htop
    btop
    claude-code

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

    # Formatters and CLI tools (same reason)
    gcc # tree-sitter CLI calls cc to compile parsers
    tree-sitter
    stylua
    prettierd
    ruff
    shfmt
    gdtoolkit_4 # provides gdformat / gdlint
  ];
}
