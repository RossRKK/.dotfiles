# kache, the Rust/C compiler cache, installed the way its docs describe for Nix
# (docs/getting-started/installation.mdx) but as home-manager rather than NixOS.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  kache = lib.getExe pkgs.kache;
  settings = pkgs.formats.toml { };
in
{
  home.packages = [ pkgs.kache ];

  home.sessionVariables.RUSTC_WRAPPER = kache;

  # The cargo shim lets the daemon see `cargo test`/`run` holding a target, so
  # cleanup never deletes one mid-run; the C/C++ shims cache build-script compiles.
  home.sessionPath = [ "${pkgs.kache}/shims" ];

  # Worktree targets otherwise grow without bound: by default kache only drops
  # units unused for 30 days and never removes idle targets.
  xdg.configFile."kache/config.toml".source = settings.generate "kache-config" {
    cache = {
      local_max_size = "30GiB";
      auto_clean_unused_units_days = 1;
      auto_clean_idle_targets_days = 3;
      auto_recover_targets = true;
      auto_recover_min_free_bytes = 100 * 1024 * 1024 * 1024;
    };
  };

  # Hourly cleanup only runs in the daemon, so keep one running rather than
  # relying on builds to start it.
  systemd.user.services.kache = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    Unit.Description = "kache build cache daemon";
    Service = {
      ExecStart = "${kache} daemon run";
      Restart = "on-failure";
      RestartSec = "5s";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
