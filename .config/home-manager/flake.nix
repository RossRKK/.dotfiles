{
  description = "Ross's home-manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
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

  outputs = { self, nixpkgs, home-manager, plasma-manager, ... }:
    let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
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
