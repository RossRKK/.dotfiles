{ config, pkgs, ... }:

{
  imports = [
    ../base.nix
  ];

  home.shellAliases = {
    hms = "home-manager switch --flake ~/.config/home-manager#rosskelso@work";
  };

  home.username = "rosskelso";
  home.homeDirectory = "/home/rosskelso";
  home.stateVersion = "26.05";
}
