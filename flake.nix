{
  description = "Ross's home-manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    # 26.05's atmos (1.194.1) predates the `atmos ansible` command the infra
    # provisioning workflows use, and its poethepoet (0.28) predates the `uv`
    # executor type the ionics monorepo sets in [tool.poe] (needs >=0.44),
    # and its svelte-language-server (0.17.31) predates the 0.18.x line that
    # understands Svelte 5.5x runes and TypeScript 6 (false errors on runes
    # and <script> blocks otherwise); take them from unstable until stable
    # catches up.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, plasma-manager, ... }:
    let
      # Linux hosts (personal, work) take atmos/poethepoet/opentofu from
      # unstable, see the nixpkgs-unstable input comment above.
      pkgsLinux = system:
        let
          pkgs-unstable = import nixpkgs-unstable {
            inherit system;
            config.allowUnfree = true;
          };
        in
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ (final: prev: {
            atmos = pkgs-unstable.atmos;
            poethepoet = pkgs-unstable.poethepoet;
            opentofu = pkgs-unstable.opentofu;
            svelte-language-server = pkgs-unstable.svelte-language-server;
          }) ];
        };

      pkgsDarwin = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in {
      homeConfigurations."rossrkk@personal" = home-manager.lib.homeManagerConfiguration {
        pkgs = pkgsLinux "x86_64-linux";
        modules = [
          plasma-manager.homeModules.plasma-manager
          ./hosts/personal.nix
        ];
      };

      homeConfigurations."rosskelso@work" = home-manager.lib.homeManagerConfiguration {
        pkgs = pkgsLinux "x86_64-linux";
        modules = [ ./hosts/work.nix ];
      };

      # macOS (Apple Silicon), home-manager standalone — no nix-darwin.
      homeConfigurations."rossrkk@aether" = home-manager.lib.homeManagerConfiguration {
        pkgs = pkgsDarwin "aarch64-darwin";
        modules = [ ./hosts/aether.nix ];
      };
    };
}
