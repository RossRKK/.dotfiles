{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Single source of truth for where this repo is checked out.
  dotfilesDir = "${config.home.homeDirectory}/.dotfiles";

  # Symlink a path (relative to the repo root) into the Nix store's view.
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/${path}";
in
{
  # Home for repo-tracked scripts (clipboard-copy, nvim-dev — see home.file).
  home.sessionPath = [ "$HOME/.local/bin" ];

  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      fish_vi_key_bindings
      # fish 4 applies the key-binding switch with `set --no-event`, so the
      # call above never fires autopair's --on-variable rebind handler and it
      # ends up with no bindings in insert mode; re-run it explicitly.
      _autopair_fish_key_bindings
      any-nix-shell fish --info-right | source
    '';
    plugins = [
      {
        name = "fzf-fish";
        src = pkgs.fishPlugins.fzf-fish.src;
      }
      {
        name = "autopair";
        src = pkgs.fishPlugins.autopair.src;
      }
    ];
    functions = {
      # Login nag: how many flake inputs are behind upstream, and how far the
      # local ~/.dotfiles checkout has drifted from its remote. Reads a cache
      # written by dotfiles-nag-refresh so the prompt never blocks; refreshes
      # in the background (disowned) when the cache is missing or older than 6h.
      fish_greeting = ''
        set -l cache "$HOME/.cache/dotfiles-nag"

        # Kick off a background refresh if the cache is stale (>6h) or absent.
        set -l stale 1
        if test -f "$cache"
          set -l age (math (date +%s) - (stat -c %Y "$cache"))
          test "$age" -lt 21600; and set stale 0
        end
        if test "$stale" -eq 1
          fish -c 'dotfiles-nag-refresh' >/dev/null 2>&1 &
          disown
        end

        test -f "$cache"; or return

        set -l outdated (grep '^outdated ' "$cache" | cut -d' ' -f2)
        set -l ahead (grep '^ahead ' "$cache" | cut -d' ' -f2)
        set -l behind (grep '^behind ' "$cache" | cut -d' ' -f2)

        # A plural "s" unless n == 1. Kept in a variable because an *empty*
        # command substitution spliced into a concatenated word makes fish
        # drop the entire word (empty-list cartesian product).
        function __nag_s
          if test "$argv[1]" -eq 1
            echo -n ""
          else
            echo -n s
          end
        end

        set -l msgs
        if test -n "$outdated"; and test "$outdated" -gt 0
          set -l s (__nag_s $outdated)
          set -a msgs (set_color yellow)"$outdated flake input$s behind upstream"(set_color normal)" — run "(set_color cyan)"nix flake update --flake ~/.dotfiles/.config/home-manager && hms"(set_color normal)
        end
        if test -n "$behind"; and test "$behind" -gt 0
          set -l s (__nag_s $behind)
          set -a msgs (set_color red)"~/.dotfiles is $behind commit$s behind"(set_color normal)
        end
        if test -n "$ahead"; and test "$ahead" -gt 0
          set -l s (__nag_s $ahead)
          set -a msgs (set_color blue)"~/.dotfiles is $ahead commit$s ahead"(set_color normal)" — run "(set_color cyan)"git -C ~/.dotfiles push"(set_color normal)
        end
        functions -e __nag_s

        for m in $msgs
          echo "  $m"
        end
      '';
    };
  };

  programs.starship.enable = true;

  programs.git = {
    enable = true;
    lfs.enable = true;
    signing = {
      format = "ssh";
      # SSH keys are managed outside nix; same path on both hosts.
      key = "~/.ssh/id_ed25519.pub";
      signByDefault = true;
    };
    settings = {
      user.name = "Ross Kelso";
      # user.email is set per-host (personal vs. work).
      merge.ff = "only";
      init.defaultBranch = "main";
    };
  };

  programs.jujutsu = {
    enable = true;
    settings = {
      user.name = "Ross Kelso";
      # user.email is set per-host (personal vs. work), same as git.
      ui.default-command = "log";
      # Git-style conflict markers (<<< === >>>) so nvim's git-conflict.nvim
      # (see .config/nvim/lua/plugins/git.lua) can parse and resolve conflicts
      # in place. jj's native markers are 3+ sided and git-conflict can't read
      # them; N-sided conflicts still fall back to jj's diff format.
      ui.conflict-marker-style = "git";
      # Reuse the same SSH signing key as git.
      signing = {
        behavior = "own";
        backend = "ssh";
        key = "~/.ssh/id_ed25519.pub";
      };
    };
  };

  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
  };

  programs.zoxide = {
    enable = true;
    options = [ "--cmd cd" ];
  };

  programs.fzf = {
    enable = true;
    # The fzf.fish plugin (programs.fish.plugins) provides its own richer
    # bindings; the stock integration would fight it over Ctrl+R.
    enableFishIntegration = false;
  };

  programs.home-manager.enable = true;

  # These modules only write config files when their `settings` options are
  # set, so plain `enable` just installs the package and the out-of-store
  # symlinks below (lazygit, jjui) stay authoritative. Neovim deliberately
  # stays a plain package: programs.neovim's wrapper always generates an
  # init.lua, which collides with the symlinked ~/.config/nvim.
  programs.lazygit.enable = true;
  programs.jjui.enable = true; # TUI for jujutsu (jj), wired to <C-g> in nvim (jj repos; lazygit else)
  programs.htop.enable = true;
  programs.btop.enable = true;
  programs.claude-code.enable = true;
  programs.ripgrep.enable = true;
  programs.fd.enable = true;
  programs.uv = {
    enable = true;
    # Always use uv-managed (python-build-standalone) interpreters: they load
    # through nix-ld, so manylinux wheels (grpcio etc.) find libstdc++ via
    # programs.nix-ld.libraries. The nixpkgs python bypasses nix-ld and needs
    # a global LD_LIBRARY_PATH hack to import those wheels.
    settings.python-preference = "only-managed";
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN = "1";
  };

  # Each key maps to `.config/<key>` in the repo.
  xdg.configFile =
    lib.genAttrs
      [
        "nvim"
        "lazygit"
        "jjui"
        "starship.toml"
        "nix/nix.conf"
      ]
      (name: {
        source = link ".config/${name}";
      });

  # Each key is also its path relative to the repo root.
  home.file =
    lib.genAttrs
      [
        ".tmux.conf"
        ".local/bin/clipboard-copy"
        ".local/bin/nvim-dev"
        ".local/bin/dotfiles-nag-refresh"
      ]
      (path: {
        source = link path;
      });

  home.packages = with pkgs; [
    # Plain package on purpose (see comment above programs.lazygit): the
    # programs.neovim wrapper would generate an init.lua that collides with
    # the symlinked ~/.config/nvim.
    neovim
    # The nix neovim wrapper puts wl-copy on its own PATH; install it user-wide
    # too so locally-built nvim (e.g. ~/dev/neovim) gets a clipboard provider.
    wl-clipboard

    # tmux stays a plain package: programs.tmux always generates its own
    # ~/.config/tmux/tmux.conf, which the symlinked ~/.tmux.conf would shadow.
    tmux

    # Runtimes
    python3
    nodejs
    # rustup rather than nixpkgs rustc/cargo so per-project rust-toolchain.toml
    # pins (e.g. liboi's nightly + rust-src) are respected; it also proxies
    # rustfmt/clippy/rust-analyzer, which would collide if installed directly
    rustup

    # CLI tools
    any-nix-shell
    gcx # Grafana Cloud CLI
    gnumake # plugin test suites (fishmonger.nvim etc.) drive nvim via make test
    imagemagick
    terraform

    # LSP servers (used by neovim via lspconfig; installed here so Mason doesn't
    # try to download pre-compiled binaries that won't run on NixOS)
    basedpyright
    typescript-language-server
    svelte-language-server
    lua-language-server
    yaml-language-server
    vscode-langservers-extracted # provides jsonls
    terraform-ls
    marksman
    helm-ls
    nixd

    # Debug adapters (nvim-dap; debugpy is not here because the python adapter
    # runs debugpy out of each project's venv, see dap.lua)
    vscode-js-debug # provides js-debug (pwa-node adapter)
    vscode-extensions.vadimcn.vscode-lldb.adapter # provides codelldb (used by rustaceanvim)

    # Formatters and CLI tools (same reason)
    gcc # tree-sitter CLI calls cc to compile parsers
    lld
    llvm
    tree-sitter
    stylua
    prettierd
    ruff
    shfmt
    shellcheck
    gdtoolkit_4 # provides gdformat / gdlint
    nixfmt # official nixfmt (RFC 166)
  ];
}
