-- Highlight and search TODO / FIXME / HACK / NOTE / WARN / PERF comments across
-- the project. Highlighting is automatic on load; <leader>ft lists them in
-- Trouble (todo-comments has no snacks-picker source), same backing as the
-- <leader>lt list trouble.lua registers.
return {
  {
    "folke/todo-comments.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    event = { "BufReadPost", "BufNewFile" },
    opts = {},
    keys = {
      { "<leader>ft", "<cmd>TodoTrouble<cr>", desc = "Find TODOs" },
    },
  },
}
