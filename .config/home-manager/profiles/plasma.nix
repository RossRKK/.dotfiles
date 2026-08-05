{ config, lib, ... }:

# KDE Plasma configuration via plasma-manager.
{
  # Launchers a host wants pinned on top of the shared base set below — e.g. a
  # desktop that has Steam or Discord installed. Each entry is a launcher URL
  # like "applications:steam.desktop".
  options.taskbar.extraLaunchers = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "applications:discord.desktop" ];
    description = "Extra taskbar launchers appended to the base set.";
  };

  config.programs.plasma = {
    enable = true;

    workspace = {
      # Force dark mode and keep it there across rebuilds.
      lookAndFeel = "org.kde.breezedark.desktop";
      colorScheme = "BreezeDark";
      # Default desktop background: earthrise over the lunar surface. The image
      # lives in the repo so it's reproducible on a fresh machine.
      wallpaper = ../wallpapers/earth-set.jpg;
    };

    # One bottom panel per monitor (screen = "all"), each with the same pinned
    # launchers. Defining panels here means plasma-manager owns the layout.
    panels = [
      {
        location = "bottom";
        screen = "all";
        widgets = [
          "org.kde.plasma.kickoff"
          {
            iconTasks.launchers = [
              "applications:systemsettings.desktop"
              "applications:org.kde.dolphin.desktop"
              "applications:firefox.desktop"
              "applications:org.kde.konsole.desktop"
              "applications:com.mitchellh.ghostty.desktop"
            ] ++ config.taskbar.extraLaunchers;
          }
          "org.kde.plasma.marginsseparator"
          "org.kde.plasma.systemtray"
          "org.kde.plasma.digitalclock"
        ];
      }
    ];
  };
}
