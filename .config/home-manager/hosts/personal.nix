{ config, pkgs, ... }:

{
  imports = [
    ../base.nix
    ../profiles/desktop.nix
    ../profiles/personal.nix
  ];

  home.shellAliases = {
    hms = "home-manager switch --flake ~/.dotfiles/.config/home-manager#rossrkk@personal";
  };

  home.username = "rossrkk";
  home.homeDirectory = "/home/rossrkk";
  home.stateVersion = "26.05";
}
