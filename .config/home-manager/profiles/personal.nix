{ config, pkgs, ... }:

{
  programs.git.settings.user.email = "ross@rosskelso.com";
  programs.jujutsu.settings.user.email = "ross@rosskelso.com";

  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

  home.packages = with pkgs; [
    (symlinkJoin {
      name = "discord";
      paths = [ discord ];
      buildInputs = [ makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/discord \
          --add-flags "--enable-features=WebRTCPipeWireCapturer"
      '';
    })
  ];
}
