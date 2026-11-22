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
      on_highlights = function(highlights, colors)
        highlights["@keyword.import"] = { link = "@keyword" }
        -- tokyonight blends DiffChange from blue7 (already a dark blue) at only
        -- 15%, which is near-invisible against the background; add and delete
        -- use brighter hues at 25%. Bring the change tint up to match, so the
        -- inline diff (gitsigns linehl) and vimdiff read as three colours.
        highlights.DiffChange = { bg = require("tokyonight.util").blend_bg(colors.blue7, 0.35) }
        -- tokyonight draws rendered tables' borders red and orange and their header blue; keep them calm.
        highlights.RenderMarkdownTableHead = { fg = colors.comment }
        highlights.RenderMarkdownTableRow = { fg = colors.comment }
        -- Markdown's only bare @markup.heading capture is a table's header cells.
        highlights["@markup.heading.markdown"] = { fg = colors.fg, bold = true }
      end,
    },
    config = function(_, opts)
      require("tokyonight").setup(opts)
      vim.cmd("colorscheme tokyonight")
    end,
  },
}
