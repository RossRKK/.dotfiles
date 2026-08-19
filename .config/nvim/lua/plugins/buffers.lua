return {
  {
    -- Tab bar showing one tab per open buffer; cycle with <S-l>/<S-h>.
    "akinsho/bufferline.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    event = "VeryLazy",
    opts = {
      options = {
        diagnostics = "nvim_lsp",
        -- Vim's buffer list is global, but a workspace tabpage is one project
        -- (see config/workspace.lua) -- so show only the buffers under this
        -- tab's cwd, and let the rest belong to their own tab. Buffers with no
        -- file on disk (terminals, scratch) are kept: they're not another
        -- project's, and hiding them would make them unreachable from the bar.
        -- <S-l>/<S-h> are mapped to BufferLineCycleNext/Prev (not bnext) so
        -- cycling honours this filter instead of walking the global list.
        custom_filter = function(buf)
          local file = vim.api.nvim_buf_get_name(buf)
          if file == "" or vim.bo[buf].buftype ~= "" then
            return true
          end
          local cwd = require("config.workspace").cwd()
          return vim.startswith(vim.fs.normalize(file), vim.fs.normalize(cwd) .. "/")
        end,
        -- Route clicks to the main window: single-main-buffer layout, so a
        -- click while the terminal/explorer is focused must not replace it.
        left_mouse_command = function(bufnr)
          require("config.windows").goto_main_window()
          vim.cmd("buffer " .. bufnr)
        end,
        -- The default close command is `bdelete!`, which lets Vim drop the
        -- replacement buffer into whatever window it likes — hijacking the
        -- explorer/terminal and wrecking the layout. Snacks.bufdelete switches
        -- each window showing the buffer first, preserving the layout.
        close_command = function(bufnr)
          require("config.windows").goto_main_window()
          require("snacks").bufdelete(bufnr)
        end,
        right_mouse_command = function(bufnr)
          require("config.windows").goto_main_window()
          require("snacks").bufdelete(bufnr)
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
