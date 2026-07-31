{ config, pkgs, ... }:

{
  imports = [
    ../base.nix
  ];

  home.shellAliases = {
    hms = "home-manager switch --flake ~/.dotfiles/.config/home-manager#rosskelso@work";
  };

  home.packages = with pkgs; [
    ansible
  ];

  home.username = "rosskelso";
  home.homeDirectory = "/home/rosskelso";
  home.stateVersion = "26.05";
}
