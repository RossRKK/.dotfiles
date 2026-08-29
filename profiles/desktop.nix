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
    neovide
    nerd-fonts._0xproto
  ];
}
