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
      ]
      (path: {
        source = link path;
      });

  home.packages = with pkgs; [
    # Plain package on purpose (see comment above programs.lazygit): the
    # programs.neovim wrapper would generate an init.lua that collides with
    # the symlinked ~/.config/nvim.
    neovim

    # tmux stays a plain package: programs.tmux always generates its own
    # ~/.config/tmux/tmux.conf, which the symlinked ~/.tmux.conf would shadow.
    tmux

    # Runtimes
    python3
    uv
    nodejs
    # rustup rather than nixpkgs rustc/cargo so per-project rust-toolchain.toml
    # pins (e.g. liboi's nightly + rust-src) are respected; it also proxies
    # rustfmt/clippy/rust-analyzer, which would collide if installed directly
    rustup

    # CLI tools
    any-nix-shell
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
