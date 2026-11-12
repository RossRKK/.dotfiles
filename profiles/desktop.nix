{ config, pkgs, ... }:

{
  imports = [
    ./plasma.nix
  ];

  xdg.configFile."ghostty".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/.config/ghostty";

  xdg.configFile."neovide".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/.config/neovide";

  home.packages = with pkgs; [
    ghostty
    # Neovide's nvim gives each agent its own worktree (util/worktree.lua); terminal nvim stays per branch.
    (symlinkJoin {
      name = "neovide";
      paths = [ neovide ];
      nativeBuildInputs = [ makeWrapper ];
      postBuild = "wrapProgram $out/bin/neovide --set AGENT_WORKTREES 1";
    })
    nerd-fonts._0xproto
  ];
}
