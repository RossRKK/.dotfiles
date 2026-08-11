{ config, pkgs, ... }:

{
  imports = [
    ../base.nix
  ];

  programs.git.settings.user.email = "ross@rosskelso.com";
  programs.jujutsu.settings.user.email = "ross@rosskelso.com";

  # This Nix-built fish reports an empty $__fish_sysconfdir, so it never scans
  # /etc/fish/conf.d — the usual place Nix's per-shell PATH setup would live.
  # Source it directly instead. shellInit (not interactiveShellInit) so it
  # also applies to non-interactive/login shells, matching what nix-daemon.sh
  # does for zsh/bash via /etc/zshrc and /etc/bashrc.
  programs.fish.shellInit = ''
    if test -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish
        source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish
    end
  '';

  home.shellAliases = {
    hms = "home-manager switch --flake ~/.dotfiles/.config/home-manager#rossrkk@aether";
  };

  home.username = "rossrkk";
  home.homeDirectory = "/Users/rossrkk";
  home.stateVersion = "26.05";
}
