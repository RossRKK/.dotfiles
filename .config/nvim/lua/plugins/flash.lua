-- Fast in-buffer motion: jump to any visible location in a couple of keystrokes,
-- with treesitter-node selection and operator-pending "remote" jumps.
--
-- s/S shadow Vim's substitute (cl/cc still do that verbatim), which CLAUDE.md
-- warns against -- but the on-screen jump is flash's whole ergonomic point and
-- substitute is trivially reachable via cl/cc, so the trade is worth it. The
-- operator-pending r/R only shadow in o-mode, so normal-mode r (replace char)
-- and R (replace mode) are untouched.
return {
  {
    "folke/flash.nvim",
    event = "VeryLazy", -- load early so f/t/F/T and / get flash's labels too
    ---@type Flash.Config
    opts = {},
    keys = {
      {
        "s",
        mode = { "n", "x", "o" },
        function()
          require("flash").jump()
        end,
        desc = "Flash jump",
      },
      {
        "S",
        mode = { "n", "x", "o" },
        function()
          require("flash").treesitter()
        end,
        desc = "Flash treesitter select",
      },
      {
        "r",
        mode = "o",
        function()
          require("flash").remote()
        end,
        desc = "Remote flash (operate elsewhere)",
      },
      {
        "R",
        mode = "o",
        function()
          require("flash").treesitter_search()
        end,
        desc = "Treesitter search",
      },
    },
  },
}
