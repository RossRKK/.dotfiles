-- A navigable panel for diagnostics, LSP references/definitions, symbols, the
-- quickfix list, and TODOs -- turns "N problems somewhere" into a grouped,
-- jump-to list. The <leader>lt source is backed by todo-comments.lua.
return {
  {
    "folke/trouble.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    cmd = "Trouble",
    opts = {},
    keys = {
      { "<leader>ld", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics (workspace)" },
      { "<leader>lD", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Diagnostics (buffer)" },
      { "<leader>lr", "<cmd>Trouble lsp_references toggle<cr>", desc = "LSP references" },
      { "<leader>ls", "<cmd>Trouble symbols toggle<cr>", desc = "Symbols" },
      { "<leader>ll", "<cmd>Trouble lsp toggle<cr>", desc = "LSP defs / refs / impls" },
      { "<leader>lq", "<cmd>Trouble qflist toggle<cr>", desc = "Quickfix list" },
      { "<leader>lt", "<cmd>Trouble todo toggle<cr>", desc = "TODOs" },
    },
  },
}
