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

  writer = pkgs.writeShellApplication {
    name = "write-windows-neovide-config";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ../.local/bin/write-windows-neovide-config;
  };
in
{
  # Activation drops the login PATH; WSL keeps wslpath in /bin and cmd.exe in System32.
  home.activation.windowsNeovide = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    PATH="$PATH:/bin:$(/bin/wslpath -u 'C:\Windows\System32' 2>/dev/null)" \
      run ${writer}/bin/write-windows-neovide-config ${windowsConfig}
  '';
}
