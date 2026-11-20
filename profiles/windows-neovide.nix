{ pkgs, lib, ... }:

# Windows Neovide, run from WSL, reads %APPDATA%\neovide\config.toml and sees
# only fonts installed on Windows, so each switch writes both there.
let
  shared = builtins.fromTOML (builtins.readFile ../.config/neovide/config.toml);

  windowsConfig = (pkgs.formats.toml { }).generate "neovide-config.toml" (
    shared
    // {
      wsl = true;
      # Neovide's nvim gives each agent its own worktree (util/worktree.lua).
      neovim-bin = "env AGENT_WORKTREES=1 nvim";
    }
  );

  installer = pkgs.writeShellApplication {
    name = "install-windows-neovide";
    runtimeInputs = with pkgs; [
      coreutils
      diffutils
      fontconfig
    ];
    text = builtins.readFile ../.local/bin/install-windows-neovide;
  };

  upright0xproto = pkgs.callPackage ../0xproto-upright.nix { };
  symbolFallbackFonts = pkgs.callPackage ../symbol-fallback-fonts.nix { };
in
{
  # Activation drops the login PATH; WSL keeps wslpath in /bin and Windows' tools in System32.
  home.activation.windowsNeovide = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    PATH="$PATH:/bin:$(/bin/wslpath -u 'C:\Windows\System32' 2>/dev/null)" \
      run ${installer}/bin/install-windows-neovide ${windowsConfig} \
        ${upright0xproto}/share/fonts/truetype/NerdFonts/0xProto/0xProtoNerdFontMono-*.ttf \
        ${symbolFallbackFonts}/share/fonts/*/*
  '';
}
