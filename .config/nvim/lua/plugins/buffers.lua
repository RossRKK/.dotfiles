return {
  {
    -- Tab bar showing one tab per open buffer; cycle with <S-l>/<S-h>.
    "akinsho/bufferline.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    event = "VeryLazy",
    opts = {
      options = {
        diagnostics = "nvim_lsp",
        -- Route clicks to the main window: single-main-buffer layout, so a
        -- click while the terminal/explorer is focused must not replace it.
        left_mouse_command = function(bufnr)
          require("config.windows").goto_main_window()
          vim.cmd("buffer " .. bufnr)
        end,
      },
    },
  },
  {
    -- Buffer "garbage collection": auto-close buffers left untouched for a while
    -- so hidden buffers stop piling up. Never closes unsaved or currently-visible
    -- buffers (plugin defaults), so it only reaps genuinely-idle ones.
    "chrisgrieser/nvim-early-retirement",
    event = "VeryLazy",
    opts = {
      retirementAgeMins = 20,
      -- Keep a few around even if idle, so cycling with <S-l>/<S-h> isn't empty.
      minimumBufferNum = 4,
      -- Don't retire special/tool buffers.
      ignoredFiletypes = { "fishmonger", "neo-tree", "gitcommit", "help", "qf" },
      -- A brief notice when one is closed, so the behaviour isn't invisible.
      notificationOnAutoClose = true,
    },
  },
}
