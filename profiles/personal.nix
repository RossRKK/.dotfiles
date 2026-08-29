{ config, ... }:

{
  programs.git.settings.user.email = "ross@rosskelso.com";
  programs.jujutsu.settings.user.email = "ross@rosskelso.com";

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

  # Launchers for apps the system flake (chaos.nix) installs on this desktop —
  # pinning them is user-level taste, installing them is the machine's job.
  taskbar.extraLaunchers = [
    "applications:discord.desktop"
    "applications:steam.desktop"
  ];
}
