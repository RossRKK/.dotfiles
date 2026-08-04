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
      any-nix-shell fish --info-right | source
    '';
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

  home.sessionVariables = {
    EDITOR = "nvim";
    CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN = "1";
  };

  # Install nvim plugins at the commits pinned in lazy-lock.json as part of
  # the switch, so a fresh machine gets a fully working nvim with no
  # first-launch bootstrap. Runs after linkGeneration so ~/.config/nvim
  # exists; a no-op when everything already matches the lockfile. Non-fatal:
  # if it fails (e.g. offline), lazy installs whatever is missing on the next
  # nvim launch, as before.
  home.activation.restoreNvimPlugins = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    (
      export PATH="${lib.makeBinPath [ pkgs.neovim pkgs.git ]}:$PATH"
      run nvim --headless "+Lazy! restore" +qa
    ) || verboseEcho "Lazy restore failed; nvim will bootstrap missing plugins on first launch"
  '';

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
    home-manager
    neovim
    lazygit
    jjui # TUI for jujutsu (jj), wired to <C-g> in nvim (jj repos; lazygit else)
    tmux
    htop
    btop
    claude-code

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
    ripgrep
    fd
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
