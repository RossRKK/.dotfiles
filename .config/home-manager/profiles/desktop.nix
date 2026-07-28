{ config, pkgs, ... }:

{
  xdg.configFile."ghostty".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/.config/ghostty";

  home.packages = with pkgs; [
    ghostty
    nerd-fonts._0xproto
  ];
}
