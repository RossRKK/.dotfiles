{
  description = "Ross's home-manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    # 26.05's atmos (1.194.1) predates the `atmos ansible` command the infra
    # provisioning workflows use, and its poethepoet (0.28) predates the `uv`
    # executor type the ionics monorepo sets in [tool.poe] (needs >=0.44);
    # take both from unstable until stable catches up.
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
      system = "x86_64-linux";
      pkgs-unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ (final: prev: {
          atmos = pkgs-unstable.atmos;
          poethepoet = pkgs-unstable.poethepoet;
          opentofu = pkgs-unstable.opentofu;
        }) ];
      };
    in {
      homeConfigurations."rossrkk@personal" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          plasma-manager.homeModules.plasma-manager
          ./hosts/personal.nix
        ];
      };

      homeConfigurations."rosskelso@work" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./hosts/work.nix ];
      };
    };
}
