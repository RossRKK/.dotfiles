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
    # nvim's <leader>tw creates worktrees under <repo>/.worktrees/ (see
    # .config/nvim/lua/util/worktree.lua). Ignoring it globally keeps them out of
    # every repo's git status without touching each repo's .gitignore.
    ignores = [ ".worktrees/" ];
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
        # Claude Code hook publishing each session's state for fishmonger's
        # agent view. Only the script is symlinked here; the settings.json
        # stanza that wires it to the hook events is merged in by the
        # claude-agent-status-hooks activation script below, because that file
        # is co-owned with Claude itself (model, theme) and cannot be generated.
        ".claude/hooks/agent-status"
      ]
      (path: {
        source = link path;
      });

  # Wire agent-status into Claude Code's hook events.
  #
  # ~/.claude/settings.json can't be a managed symlink: Claude rewrites it in
  # place when you change model or theme, and a read-only store path would
  # either break that or be clobbered. So instead of owning the file we own one
  # key in it, merging our `hooks` block over whatever is already there on every
  # `hms`. `*` recurses into objects, so Claude's keys survive; the hooks value
  # itself is replaced wholesale, which is what we want -- this repo is the
  # source of truth for the wiring, and stale event lists should disappear.
  home.activation.claude-agent-status-hooks =
    let
      hook = event: {
        hooks = [
          {
            type = "command";
            command = "${config.home.homeDirectory}/.claude/hooks/agent-status ${event}";
          }
        ];
      };
      # Mirrors the event table in the header of .claude/hooks/agent-status.
      hooks.hooks = {
        UserPromptSubmit = [ (hook "busy") ];
        PostToolUse = [ (hook "busy") ];
        PreToolUse = [ (hook "tool") ];
        Notification = [ (hook "notify") ];
        Stop = [ (hook "stop") ];
        SessionEnd = [ (hook "end") ];
      };
      hooksFile = (pkgs.formats.json { }).generate "claude-agent-status-hooks.json" hooks;
    in
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settings="${config.home.homeDirectory}/.claude/settings.json"
      $DRY_RUN_CMD mkdir -p "$(dirname "$settings")"
      # A missing or unparseable file merges from {} rather than aborting the
      # switch -- the wiring is worth more than whatever was in there.
      existing=$(${pkgs.jq}/bin/jq -e . "$settings" 2>/dev/null) || existing='{}'
      # Stage into a temp file and install it with mv, so the write is atomic
      # (Claude may be running) and so --dry-run really is dry: a redirection
      # after $DRY_RUN_CMD would truncate the file regardless.
      tmp=$(mktemp)
      printf '%s' "$existing" |
        ${pkgs.jq}/bin/jq --slurpfile new ${hooksFile} '. * $new[0]' >"$tmp"
      $DRY_RUN_CMD mv $VERBOSE_ARG "$tmp" "$settings"
      rm -f "$tmp"
    '';

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
    jq # .claude/hooks/agent-status parses its hook payloads with it
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
  ] ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    # The nix neovim wrapper puts wl-copy on its own PATH; install it user-wide
    # too so locally-built nvim (e.g. ~/dev/neovim) gets a clipboard provider.
    # Wayland-only, so skip it on hosts (e.g. macOS) that can't build it.
    wl-clipboard
  ];
}
