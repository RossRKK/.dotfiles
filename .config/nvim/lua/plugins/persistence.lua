return {
  {
    "folke/persistence.nvim",
    lazy = false, -- must load before VimEnter so the save hook is registered
    config = function()
      -- Remember open files only, not window layout (our explorer.lua VimEnter
      -- handler owns the tree/editor arrangement) or terminals.
      vim.o.sessionoptions = "buffers,curdir,folds"
      require("persistence").setup()
    end,
  },
}
