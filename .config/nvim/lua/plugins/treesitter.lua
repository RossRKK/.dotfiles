return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").setup({
        ensure_installed = {
          "lua", "vim", "vimdoc",
          "python", "javascript", "typescript", "tsx",
          "rust",
          "svelte",
          "markdown", "markdown_inline",
          "yaml", "json", "toml",
          "hcl",
          "bash",
          "html", "css",
        },
      })
    end,
  },
}
