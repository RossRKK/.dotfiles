return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "night",
      styles = { comments = { italic = false } },
      -- tokyonight colours from/import the same blue as module names, which reads
      -- oddly; align them with the general keyword colour (as on class/def).
      on_highlights = function(highlights)
        highlights["@keyword.import"] = { link = "@keyword" }
      end,
    },
    config = function(_, opts)
      require("tokyonight").setup(opts)
      vim.cmd("colorscheme tokyonight")
    end,
  },
}
