# The nvim Ross runs: neovim (neovim.nix) wrapped with every plugin and the Lua
# config in .config/nvim, all from the store, so nothing changes until a switch.
# lazy.nvim still loads the plugins, from these store paths (config/lazy.lua).
# See docs/nvim-nix-migration.md.
inputs:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  fromInput = pname: input: config.nvim-lib.mkPlugin pname inputs.${input};
  # From their own nixpkgs input, see flake.nix; neovim itself stays on the system's.
  # Unfree allowed as for the system's pkgs: nixpkgs marks git-conflict.nvim unfree.
  inherit
    (import inputs.nixpkgs-nvim-plugins {
      inherit (pkgs.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    })
    vimPlugins
    ;

  # Named as lazy.nvim names them: their repo's basename.
  plugins = with vimPlugins; {
    # lazy's own spec, for the copy init.lua already loaded from specs.loader.
    "lazy.nvim" = lazy-nvim;
    "agentic.nvim" = fromInput "agentic.nvim" "agentic";
    "fishmonger.nvim" = fromInput "fishmonger.nvim" "fishmonger";
    "nitpick.nvim" = fromInput "nitpick.nvim" "nitpick";
    "triage.nvim" = fromInput "triage.nvim" "triage";
    # main, not nixpkgs' 3.x: tests/neotree_leak_spec.lua fails on 3.42.0.
    "neo-tree.nvim" = fromInput "neo-tree.nvim" "neo-tree";
    "videre.nvim" = fromInput "videre.nvim" "videre";
    "graph_view_yaml_parser" = fromInput "graph_view_yaml_parser" "graph-view-yaml";
    "graph_view_toml_parser" = fromInput "graph_view_toml_parser" "graph-view-toml";
    # Newer than nixpkgs', see its input in flake.nix.
    "render-markdown.nvim" = fromInput "render-markdown.nvim" "render-markdown";
    "LuaSnip" = luasnip;
    "FixCursorHold.nvim" = FixCursorHold-nvim;
    "bufferline.nvim" = bufferline-nvim;
    "checkmate.nvim" = checkmate-nvim;
    "cmp-buffer" = cmp-buffer;
    "cmp-nvim-lsp" = cmp-nvim-lsp;
    "cmp-path" = cmp-path;
    "cmp_luasnip" = cmp_luasnip;
    "conform.nvim" = conform-nvim;
    "edgy.nvim" = edgy-nvim;
    "flash.nvim" = flash-nvim;
    "git-conflict.nvim" = git-conflict-nvim;
    "gitsigns.nvim" = gitsigns-nvim;
    "hardtime.nvim" = hardtime-nvim;
    "image.nvim" = image-nvim;
    "inc-rename.nvim" = inc-rename-nvim;
    "indent-blankline.nvim" = indent-blankline-nvim;
    "lualine.nvim" = lualine-nvim;
    "neotest" = neotest;
    "nui.nvim" = nui-nvim;
    "nvim-autopairs" = nvim-autopairs;
    "nvim-cmp" = nvim-cmp;
    "nvim-dap" = nvim-dap;
    "nvim-dap-ui" = nvim-dap-ui;
    "nvim-early-retirement" = nvim-early-retirement;
    "nvim-lint" = nvim-lint;
    "nvim-lspconfig" = nvim-lspconfig;
    "nvim-nio" = nvim-nio;
    "nvim-surround" = nvim-surround;
    "nvim-treesitter" = nvim-treesitter;
    "nvim-treesitter-textobjects" = nvim-treesitter-textobjects;
    "nvim-web-devicons" = nvim-web-devicons;
    "plenary.nvim" = plenary-nvim;
    "rustaceanvim" = rustaceanvim;
    "snacks.nvim" = snacks-nvim;
    "todo-comments.nvim" = todo-comments-nvim;
    "tokyonight.nvim" = tokyonight-nvim;
    "trouble.nvim" = trouble-nvim;
    "undotree" = undotree;
    "vim-helm" = vim-helm;
    "which-key.nvim" = which-key-nvim;
  };
  pluginDirs = pkgs.linkFarm "nvim-plugins" (
    lib.mapAttrsToList (name: path: { inherit name path; }) plugins
  );
in
{
  imports = [ inputs.wrappers.lib.wrapperModules.neovim ];

  # NVIM_CONFIG_DIR runs another checkout's config (a worktree, ~/.dotfiles) on these plugins.
  settings.config_directory = lib.generators.mkLuaInline ''os.getenv("NVIM_CONFIG_DIR") or ${builtins.toJSON "${./.config/nvim}"}'';

  # No remote-plugin hosts: no plugin here needs one, and the nixpkgs neovim before this ran none.
  hosts.python3.nvim-host.enable = false;
  hosts.node.nvim-host.enable = false;
  hosts.ruby.nvim-host.enable = false;

  # ";;" keeps LuaJIT's default search paths (./?.lua etc.) under the module's
  # LUA_PATH/LUA_CPATH suffix, which replace them when unset; as nixpkgs' lua wrapper does.
  envDefault.LUA_PATH = {
    data = ";;";
    before = [ "NIX_PROPAGATED_LUA_PATH" ];
  };
  envDefault.LUA_CPATH = {
    data = ";;";
    before = [ "NIX_PROPAGATED_LUA_CPATH" ];
  };

  specs.loader = vimPlugins.lazy-nvim;

  # Parsers and their queries, collated into pack/*/start: on the runtimepath from the start.
  specs.parsers = with vimPlugins.nvim-treesitter.grammarPlugins; [
    lua
    vim
    vimdoc
    query
    python
    javascript
    typescript
    tsx
    rust
    svelte
    markdown
    markdown_inline
    yaml
    json
    toml
    hcl
    nix
    helm
    bash
    html
    css
    gdscript
    gdshader
    godot_resource
  ];

  # Every other plugin, for lazy.nvim to load (config/lazy.lua), each in a
  # directory named as lazy names it: lazy tells which plugin a require()d module
  # belongs to by that name, and loads a module it can't place without its spec's
  # opts or config. Not specs, so the plugins' own Lua rocks stay out of
  # neovim's Lua environment, as under lazy's own installs.
  info.plugin_dirs = builtins.mapAttrs (name: _: "${pluginDirs}/${name}") plugins;
}
