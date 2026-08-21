--- Close a buffer from the bar, unless it's a greeter (see close_command below).
---@param bufnr integer
local function close_buffer(bufnr)
  if vim.b[bufnr].greeter_root then
    return
  end
  require("config.windows").goto_main_window()
  require("snacks").bufdelete(bufnr)
end

return {
  {
    -- Tab bar showing one tab per open buffer; cycle with <S-l>/<S-h>. The
    -- leftmost tab is the workspace greeter (config/greeter.lua), pinned there
    -- by sort_by below.
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
          -- Greeters are per workspace and listed (config/greeter.lua), so they
          -- must be matched on their root FIRST: they carry no filename, so the
          -- "no file on disk" rule below would otherwise show every project's
          -- greeter on every project's bar.
          local root = vim.b[buf].greeter_root
          if root then
            return root == vim.fs.normalize(require("config.workspace").cwd())
          end
          local file = vim.api.nvim_buf_get_name(buf)
          if file == "" or vim.bo[buf].buftype ~= "" then
            return true
          end
          local cwd = require("config.workspace").cwd()
          return vim.startswith(vim.fs.normalize(file), vim.fs.normalize(cwd) .. "/")
        end,
        -- The greeter sits at the front of the bar, so "back to the overview" is
        -- always the same place -- the leftmost tab -- rather than wherever its
        -- buffer number happened to land it. Everything else keeps bufferline's
        -- default buffer-number order, so the files don't shuffle as you work.
        sort_by = function(a, b)
          local ga, gb = vim.b[a.id].greeter_root ~= nil, vim.b[b.id].greeter_root ~= nil
          if ga ~= gb then
            return ga
          end
          return a.id < b.id
        end,
        -- The greeter has no filename to show, and "[No Name]" says nothing.
        -- Name it for what it is; the project it belongs to is already the tab
        -- label at the other end of the bar.
        name_formatter = function(item)
          return vim.b[item.bufnr] and vim.b[item.bufnr].greeter_root and "Overview" or nil
        end,
        get_element_icon = function(item)
          if item.filetype == "snacks_dashboard" then
            return "\xef\x80\x95", "SnacksDashboardIcon" -- nf-fa-home
          end
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
        -- Closing the greeter is meaningless -- it is the workspace's floor, so
        -- the BufEnter fallback puts it straight back (as a NEW buffer, losing
        -- its place on the bar). Both close paths leave it alone instead.
        close_command = close_buffer,
        right_mouse_command = close_buffer,
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
      -- snacks_dashboard is the workspace greeter: it's idle by nature (you're
      -- not typing in it), so age is no evidence it's unwanted -- and reaping it
      -- would take the bar's first tab away mid-session.
      ignoredFiletypes = {
        "fishmonger",
        "neo-tree",
        "gitcommit",
        "help",
        "qf",
        "snacks_dashboard",
      },
      -- A brief notice when one is closed, so the behaviour isn't invisible.
      notificationOnAutoClose = true,
    },
  },
}
