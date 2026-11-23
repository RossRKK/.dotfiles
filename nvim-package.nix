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
in
{
  imports = [ inputs.wrappers.lib.wrapperModules.neovim ];

  # NVIM_CONFIG_DIR runs another checkout's config (a worktree, ~/.dotfiles) on these plugins.
  settings.config_directory = lib.generators.mkLuaInline ''os.getenv("NVIM_CONFIG_DIR") or ${builtins.toJSON "${./.config/nvim}"}'';

  # lazy.nvim decides when each plugin loads, so nix only puts them in pack/*/opt.
  specMods =
    { parentSpec ? null, ... }:
    {
      config.pluginDeps = lib.mkDefault (parentSpec.pluginDeps or "lazy");
      config.autoconfig = lib.mkDefault (parentSpec.autoconfig or false);
    };

  specs.loader = pkgs.vimPlugins.lazy-nvim;

  # The parsers themselves land in pack/*/start, so they're there before lazy loads the plugin.
  specs.treesitter.lazy = true;
  specs.treesitter.data = pkgs.vimPlugins.nvim-treesitter.withPlugins (
    p: with p; [
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
    ]
  );

  # Named as lazy.nvim names them (the repo's basename), which is how config/lazy.lua finds them.
  specs.plugins = {
    lazy = true;
    data = with pkgs.vimPlugins; [
      (fromInput "agentic.nvim" "agentic")
      (fromInput "fishmonger.nvim" "fishmonger")
      (fromInput "nitpick.nvim" "nitpick")
      (fromInput "triage.nvim" "triage")
      # main, not nixpkgs' 3.x: tests/neotree_leak_spec.lua fails on 3.42.0.
      (fromInput "neo-tree.nvim" "neo-tree")
      (fromInput "videre.nvim" "videre")
      (fromInput "graph_view_yaml_parser" "graph-view-yaml")
      (fromInput "graph_view_toml_parser" "graph-view-toml")
      # Newer than nixpkgs', see its input in flake.nix.
      (fromInput "render-markdown.nvim" "render-markdown")
      {
        data = luasnip;
        pname = "LuaSnip";
      }
      FixCursorHold-nvim
      bufferline-nvim
      checkmate-nvim
      cmp-buffer
      cmp-nvim-lsp
      cmp-path
      cmp_luasnip
      conform-nvim
      edgy-nvim
      flash-nvim
      git-conflict-nvim
      gitsigns-nvim
      hardtime-nvim
      image-nvim
      inc-rename-nvim
      indent-blankline-nvim
      lualine-nvim
      neotest
      nui-nvim
      nvim-autopairs
      nvim-cmp
      nvim-dap
      nvim-dap-ui
      nvim-early-retirement
      nvim-lint
      nvim-lspconfig
      nvim-nio
      nvim-surround
      nvim-treesitter-textobjects
      nvim-web-devicons
      plenary-nvim
      rustaceanvim
      snacks-nvim
      todo-comments-nvim
      tokyonight-nvim
      trouble-nvim
      undotree
      vim-helm
      which-key-nvim
    ];
  };
}
