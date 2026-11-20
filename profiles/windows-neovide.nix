{ pkgs, lib, ... }:

# Windows Neovide, run from WSL, reads %APPDATA%\neovide\config.toml, so each switch writes it there.
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
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ../.local/bin/install-windows-neovide;
  };
in
{
  # Activation drops the login PATH; WSL keeps wslpath in /bin and cmd.exe in System32.
  home.activation.windowsNeovide = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    PATH="$PATH:/bin:$(/bin/wslpath -u 'C:\Windows\System32' 2>/dev/null)" \
      run ${installer}/bin/install-windows-neovide ${windowsConfig}
  '';
}
