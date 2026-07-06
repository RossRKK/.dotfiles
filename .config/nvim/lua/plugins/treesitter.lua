return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main", -- the rewrite; setup()/ensure_installed of the master API is gone
    build = ":TSUpdate",
    config = function()
      local parsers = {
        "lua", "vim", "vimdoc", "query",
        "python", "javascript", "typescript", "tsx",
        "rust",
        "svelte",
        "markdown", "markdown_inline",
        "yaml", "json", "toml",
        "hcl",
        "bash",
        "html", "css",
      }

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
          if not pcall(vim.treesitter.start, ev.buf) then
            return
          end
          -- Drive folds from treesitter for buffers that have a parser. The
          -- global defaults (config/options.lua) are evaluated before start()
          -- runs on this branch, so the first foldexpr pass sees no tree and
          -- caches "no folds"; re-assert them window-local here, now the parser
          -- is live, to force folds to compute. Guarded to the window actually
          -- showing this buffer (FileType can fire for background loads).
          if vim.api.nvim_get_current_buf() == ev.buf then
            vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
            vim.wo.foldmethod = "expr"
          end
        end,
      })
    end,
  },
}
