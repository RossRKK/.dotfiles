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

  # User avatar. Plasma (kickoff, the lock screen, system settings) reads
  # ~/.face.icon; some older bits still look at ~/.face, so provide both.
  # SDDM's copy lives in /var/lib/AccountsService and is set system-side.
  config.home.file = {
    ".face.icon".source = ../images/avatar.png;
    ".face".source = ../images/avatar.png;
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

    # The lock screen has its own wallpaper setting (kscreenlockerrc), entirely
    # separate from the desktop's. Without this it falls back to stock Breeze,
    # which is why unlocking looked like the wallpaper had "reset".
    kscreenlocker.appearance.wallpaper = ../wallpapers/earth-set.jpg;

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
              "applications:neovide.desktop"
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
