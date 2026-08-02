{ config, pkgs, ... }:

{
  imports = [
    ../base.nix
  ];

  programs.git.settings.user.email = "ross.kelso@oxionics.com";

  # WSL has no systemd user session ssh-agent, so start one per shell if needed.
  programs.fish.interactiveShellInit = ''
    if test -z "$SSH_AUTH_SOCK"
        eval (ssh-agent -c) > /dev/null
    end
  '';

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
