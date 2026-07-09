return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main", -- the rewrite; setup()/ensure_installed of the master API is gone
    build = ":TSUpdate",
    config = function()
      -- Grouped by language family; stylua would put each on its own line.
      -- stylua: ignore
      local parsers = {
        "lua", "vim", "vimdoc", "query",
        "python", "javascript", "typescript", "tsx",
        "rust",
        "svelte",
        "markdown", "markdown_inline",
        "yaml", "json", "toml",
        "hcl",
        "helm", -- Go-template YAML; injects yaml + gotmpl highlighting
        "bash",
        "html", "css",
        "gdscript", "gdshader", "godot_resource",
      }

      -- Neovim detects .tscn/.tres as filetype "gdresource", but the parser is
      -- named "godot_resource" and nvim-treesitter's main branch registers no
      -- filetype->language mappings. Without this the pcall'd treesitter.start
      -- below silently no-ops on scene and resource files.
      vim.treesitter.language.register("godot_resource", "gdresource")

      -- main-branch install() builds parsers with the upstream `tree-sitter` CLI,
      -- which mason-tool-installer provisions. On a cold machine the CLI often
      -- isn't on PATH yet when this runs, so defer install() until mason signals
      -- it's finished; otherwise build straight away. (install() skips parsers
      -- already present, and highlighting is opt-in per buffer below -- there's no
      -- global `highlight = { enable = true }` on this branch.)
      local function install_parsers()
        require("nvim-treesitter").install(parsers)
      end
      if vim.fn.executable("tree-sitter") == 1 then
        install_parsers()
      else
        vim.api.nvim_create_autocmd("User", {
          pattern = "MasonToolsUpdateCompleted", -- fired by mason-tool-installer
          once = true,
          callback = install_parsers,
        })
      end

      -- Start treesitter highlighting for every buffer whose language has a parser.
      -- pcall keeps it a no-op for filetypes without one, so those fall back to
      -- Neovim's legacy regex syntax highlighting instead of erroring.
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(ev)
          pcall(vim.treesitter.start, ev.buf)
        end,
      })
    end,
  },
}
