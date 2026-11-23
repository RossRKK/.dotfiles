{
  description = "Ross's home-manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    # 26.05's atmos (1.194.1) predates the `atmos ansible` command the infra
    # provisioning workflows use, and its poethepoet (0.28) predates the `uv`
    # executor type the work monorepo sets in [tool.poe] (needs >=0.44),
    # and its svelte-language-server (0.17.31) predates the 0.18.x line that
    # understands Svelte 5.5x runes and TypeScript 6 (false errors on runes
    # and <script> blocks otherwise); take them from unstable until stable
    # catches up. Same for openspec: 26.05 ships 1.4.1, ten minor
    # releases behind upstream. And api-linter: 26.05 ships 2.3.1, behind
    # the 2.4 line a work repo's pre-commit hook pins.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    # Neovide alone, so bumping it rebuilds nothing else (kache follows unstable):
    # 0.16.2 fails to parse the API info of the 0.13 neovim built here.
    nixpkgs-neovide.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Tracks claude-code releases much faster than nixpkgs; update with
    # `nix flake update claude-code` + rebuild.
    claude-code.url = "github:sadjow/claude-code-nix";
    # Rust/C build cache (RUSTC_WRAPPER), not in nixpkgs. `stable` tracks
    # releases; its flake builds with its own rust-overlay toolchain.
    kache = {
      url = "github:kunobi-ninja/kache/stable";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    # The neovim source every host builds; see neovim.nix. Point it at any ref
    # (a release tag comes from the binary cache) and `nix flake update neovim`.
    neovim = {
      url = "github:noib3/neovim/libvterm-to-libghostty";
      flake = false;
    };
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    # Wraps neovim with its plugins and config (nvim-package.nix).
    wrappers = {
      url = "github:nix-community/nix-wrapper-modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nvim plugins nixpkgs lacks, or ships too old. Bump one with
    # `nix flake update <name>` + hms; docs/nvim-nix-migration.md.
    agentic = { url = "github:RossRKK/agentic.nvim/main"; flake = false; };
    fishmonger = { url = "github:RossRKK/fishmonger.nvim"; flake = false; };
    nitpick = { url = "github:RossRKK/nitpick.nvim"; flake = false; };
    triage = { url = "github:RossRKK/triage.nvim"; flake = false; };
    neo-tree = { url = "github:nvim-neo-tree/neo-tree.nvim/main"; flake = false; };
    videre = { url = "github:Owen-Dechow/videre.nvim"; flake = false; };
    graph-view-yaml = { url = "github:Owen-Dechow/graph_view_yaml_parser"; flake = false; };
    graph-view-toml = { url = "github:Owen-Dechow/graph_view_toml_parser"; flake = false; };
    # nixpkgs' leaves breakindentopt changed once rendering is toggled off (tests/render_markdown_spec.lua).
    render-markdown = { url = "github:MeanderingProgrammer/render-markdown.nvim"; flake = false; };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, nixpkgs-neovide, home-manager, plasma-manager, claude-code, kache, neovim, wrappers, ... }@inputs:
    let
      # The nvim every host runs, built for the given pkgs.
      nvimFor = pkgs: (wrappers.lib.evalModule (import ./nvim-package.nix inputs)).config.wrap { inherit pkgs; };

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
            openspec = pkgs-unstable.openspec;
            api-linter = pkgs-unstable.api-linter;
            neovide = nixpkgs-neovide.legacyPackages.${system}.neovide;
            claude-code = claude-code.packages.${system}.default;
            kache = kache.packages.${system}.default;
          })
          (import ./neovim.nix {
            src = neovim;
            releases = [ pkgs-unstable.neovim-unwrapped ];
          })
        ];
        };

      pkgsDarwin = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ (final: prev: {
          claude-code = claude-code.packages.${system}.default;
          kache = kache.packages.${system}.default;
        })
        (import ./neovim.nix {
          src = neovim;
          releases = [ ];
        })
      ];
      };
    in {
      packages.x86_64-linux.nvim = nvimFor (pkgsLinux "x86_64-linux");
      packages.aarch64-darwin.nvim = nvimFor (pkgsDarwin "aarch64-darwin");

      # Symbols agents print (Claude Code's checklists, ↵ line ends, timers) that
      # Neovide's font.normal chain must draw without falling back to colour emoji.
      checks.x86_64-linux.neovide-glyph-coverage =
        let pkgs = pkgsLinux "x86_64-linux"; in
        pkgs.runCommand "neovide-glyph-coverage" {
          nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.fonttools ])) ];
        } "python3 -I ${./checks/glyph-coverage.py} '✓✔✗◻◼☐☑↵⏳⌛' ${pkgs.callPackage ./0xproto-upright.nix { }}/share/fonts/truetype/NerdFonts/0xProto/0xProtoNerdFontMono-Regular.ttf ${pkgs.callPackage ./symbol-fallback-fonts.nix { }}/share/fonts/*/* && touch $out";

      homeConfigurations."rossrkk@personal" = home-manager.lib.homeManagerConfiguration {
        pkgs = pkgsLinux "x86_64-linux";
        modules = [
          plasma-manager.homeModules.plasma-manager
          ./hosts/personal.nix
        ];
      };

      # Steam Deck (SteamOS 3.x), home-manager standalone. No plasma-manager:
      # SteamOS owns desktop mode's Plasma layout, see hosts/deck.nix.
      homeConfigurations."deck@achilles" = home-manager.lib.homeManagerConfiguration {
        pkgs = pkgsLinux "x86_64-linux";
        modules = [ ./hosts/deck.nix ];
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
