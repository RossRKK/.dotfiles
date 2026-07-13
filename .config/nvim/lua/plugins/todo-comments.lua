-- Highlight and search TODO / FIXME / HACK / NOTE / WARN / PERF comments across
-- the project. Highlighting is automatic on load; <leader>ft searches them via
-- telescope, and trouble.lua adds a <leader>lt list backed by this plugin.
return {
  {
    "folke/todo-comments.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    event = { "BufReadPost", "BufNewFile" },
    opts = {},
    keys = {
      { "<leader>ft", "<cmd>TodoTelescope<cr>", desc = "Find TODOs" },
    },
  },
}
