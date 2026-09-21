{ config, pkgs, ... }:

# Steam Deck (achilles), SteamOS 3.x. Deliberately thin compared to
# hosts/personal.nix: desktop mode's Plasma session is SteamOS's own — laid out
# around gamescope and restored by system updates — so ../profiles/desktop.nix
# (and the plasma-manager config it pulls in) stays out of this host.
{
  imports = [
    ../base.nix
  ];

  programs.git.settings.user.email = "ross@rosskelso.com";
  programs.jujutsu.settings.user.email = "ross@rosskelso.com";

  # SteamOS is not NixOS: nothing system-side knows about the nix profile, so
  # home-manager has to set up XDG_DATA_DIRS (desktop entries, icons) and the
  # locale archive itself.
  targets.genericLinux.enable = true;

  # Fonts installed into the nix profile are invisible to SteamOS's fontconfig
  # until home-manager writes its own fontconfig fragment. Needed for the
  # starship prompt's glyphs in Konsole (set its font to 0xProto Nerd Font Propo).
  fonts.fontconfig.enable = true;

  home.packages = with pkgs; [
    nerd-fonts._0xproto
  ];

  # A SteamOS update replaces the root filesystem, taking the installer's
  # /etc/profile.d/nix.sh (the PATH setup for ~/.nix-profile/bin, where
  # home-manager/hms live) with it. The store itself is offloaded to /home and
  # survives, so source Nix's profile script directly rather than relying on
  # anything under /etc — same fix as hosts/aether.nix, different cause.
  programs.fish.shellInit = ''
    if test -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish
        source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish
    end
  '';

  # chsh can't stick on the Deck either — /etc/passwd and /etc/shells are on
  # that same reset-on-update rootfs — so bash hands over to fish instead.
  # Guards: interactive only (Steam launches games through non-interactive
  # shells), outermost shell only, and never when fish is already the parent.
  programs.bash = {
    enable = true;
    initExtra = ''
      if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
      fi

      if [[ $- == *i* && -z $BASH_EXECUTION_STRING && $SHLVL == 1 \
            && -x $HOME/.nix-profile/bin/fish \
            && $(ps --no-header --pid=$PPID --format=comm) != fish ]]; then
        exec "$HOME/.nix-profile/bin/fish"
      fi
    '';
  };

  home.shellAliases = {
    hms = "home-manager switch --flake ~/.dotfiles#deck@achilles";
  };

  home.username = "deck";
  home.homeDirectory = "/home/deck";
  home.stateVersion = "26.05";
}
