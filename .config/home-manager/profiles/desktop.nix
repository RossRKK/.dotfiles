{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    ghostty
    nerd-fonts._0xproto
  ];
}
