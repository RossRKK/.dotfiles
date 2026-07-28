{ config, pkgs, ... }:

{
  programs.fish = {
    enable = true;
    interactiveShellInit = "fish_vi_key_bindings";
  };

  programs.starship.enable = true;

  programs.zoxide = {
    enable = true;
    options = [ "--cmd cd" ];
  };

  home.shellAliases = {
    dotfiles = "git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME";
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN = "1";
  };

  home.packages = with pkgs; [
    home-manager
    git
    lazygit
    gh
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
