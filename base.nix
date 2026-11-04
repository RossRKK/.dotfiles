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
  # Home for repo-tracked scripts (clipboard-copy, git-worktree-clean — see home.file).
  home.sessionPath = [ "$HOME/.local/bin" ];

  programs.fish = {
    enable = true;
    interactiveShellInit = lib.mkMerge [
      ''
        fish_vi_key_bindings
        # fish 4 applies the key-binding switch with `set --no-event`, so the
        # call above never fires autopair's --on-variable rebind handler and it
        # ends up with no bindings in insert mode; re-run it explicitly.
        _autopair_fish_key_bindings
        any-nix-shell fish --info-right | source

        # Inside an nvim terminal ($NVIM set), `nvim <dir>` would nest a whole
        # second editor in the terminal buffer. Redirect that case to the
        # parent instance as a new workspace tab (tabnew + tcd + label, see
        # .config/nvim/lua/config/workspace.lua). Files and multi-arg calls
        # still nest as usual (e.g. `git commit`).
        function nvim --wraps=nvim --description 'directory opens become tabs in the parent nvim'
            if set -q NVIM; and test (count $argv) -eq 1; and test -d "$argv[1]"
                set -l dir (path resolve -- $argv[1])
                # The path lands inside a vimscript single-quoted string;
                # double any single quotes to escape them.
                set dir (string replace --all "'" "'''" -- $dir)
                command nvim --server $NVIM --remote-expr \
                    "luaeval(\"require('config.workspace').open(_A, {tab = true})\", '$dir')" >/dev/null
            else
                command nvim $argv
            end
        end
      ''
      # Must run after `zoxide init` (ordered later in this file's output)
      # since it copies and re-wraps the cd function zoxide defines.
      (lib.mkOrder 3000 ''
        # Worktree-aware cd: zoxide's frecency always ranks the main checkout
        # above a young worktree of the same repo. When a query result lands
        # in a sibling worktree of the repo we're already inside, remap it to
        # the equivalent path in the current worktree if it exists.
        # (No upstream support: https://github.com/ajeetdsouza/zoxide/discussions/970)
        #
        # Prints two lines for a directory: the checkout root and an identity
        # shared by every checkout of the same repo (the common git dir).
        function __checkout_identity --argument-names dir
            set -l root (git -C $dir rev-parse --show-toplevel 2>/dev/null)
            or return 1
            printf '%s\n%s\n' $root (git -C $dir rev-parse --path-format=absolute --git-common-dir)
        end
        functions --copy cd __zoxide_plain_cd
        function cd --wraps=cd --description 'worktree-aware zoxide cd'
            switch (count $argv)
                case 0
                    __zoxide_plain_cd
                    return
                case 1
                    # `cd -` and existing paths bypass zoxide entirely.
                    if test "$argv[1]" = -; or test -d "$argv[1]"
                        __zoxide_plain_cd $argv[1]
                        return
                    end
            end
            set -l target (zoxide query --exclude $PWD -- $argv)
            or return
            set -l current (__checkout_identity $PWD)
            and set -l target_id (__checkout_identity $target)
            and test "$target_id[1]" != "$current[1]"
            and test "$target_id[2]" = "$current[2]"
            and begin
                set -l rewritten (string replace -- $target_id[1] $current[1] $target)
                if test -d "$rewritten"
                    __zoxide_plain_cd $rewritten
                    return
                end
            end
            __zoxide_plain_cd $target
        end
      '')
    ];
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
    # nvim's <M-b>w creates worktrees under <repo>/.worktrees/ (see
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
  # symlinks below (lazygit) stay authoritative. Neovim deliberately
  # stays a plain package: programs.neovim's wrapper always generates an
  # init.lua, which collides with the symlinked ~/.config/nvim.
  programs.lazygit.enable = true;
  programs.htop.enable = true;
  programs.btop.enable = true;
  programs.claude-code = {
    enable = true;
    # A string, not a nix path, so --plugin-dir sees edits without a switch.
    plugins = [ "${dotfilesDir}/claude-plugins/agent-status" ];
  };
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
    RUSTC_WRAPPER = "${pkgs.kache}/bin/kache";
  } // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
    # bindgen dlopens libclang at build time; there's no FHS path to find it on NixOS.
    LIBCLANG_PATH = "${pkgs.libclang.lib}/lib";
    # ...and once found, libclang has no default include paths either. glibc.dev
    # is Linux-only, so this whole block is gated to Linux hosts.
    BINDGEN_EXTRA_CLANG_ARGS = "-isystem ${pkgs.glibc.dev}/include -isystem ${pkgs.libclang.lib}/lib/clang/${lib.versions.major pkgs.libclang.version}/include";
  };

  # Each key maps to `.config/<key>` in the repo.
  xdg.configFile =
    lib.genAttrs
      [
        "nvim"
        "lazygit"
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
        # `git worktree-clean` (git runs git-<name> from PATH).
        ".local/bin/git-worktree-clean"
        # Out-of-store so Claude can still append to it in place.
        ".claude/CLAUDE.md"
      ]
      (path: {
        source = link path;
      });

  home.packages =
    with pkgs;
    [
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
      bats # claude-plugins/agent-status/tests
      imagemagick
      jq # claude-plugins/agent-status parses its hook payloads with it
      openspec # spec-driven development for AI coding agents (openspec.dev)
      terraform
      cmake
      openssl

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
      buf # provides buf_ls (`buf lsp serve`) for .proto

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
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      # The nix neovim wrapper puts wl-copy on its own PATH; install it user-wide
      # too so anything outside the wrapper (terminals, scripts) gets a clipboard provider.
      # Wayland-only, so skip it on hosts (e.g. macOS) that can't build it.
      wl-clipboard
    ];
}
