return {
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("nvim-tree").setup({
        view = {
          width = 35,
          side = "left",
        },
        renderer = {
          group_empty = true,
          highlight_git = "all", -- colour both the git icon and the filename
          icons = {
            glyphs = {
              git = {
                untracked = "?",
                staged = "✓",
                unstaged = "M",
                unmerged = "U",
                renamed = "R",
                deleted = "D",
                ignored = "◌",
              },
            },
          },
        },
        filters = {
          dotfiles = false,
        },
        git = {
          enable = true,
          ignore = true,
        },
        -- Don't let the tree take over the window when opening a directory; the
        -- VimEnter handler below places it as a side panel beside an editor window.
        hijack_directories = { enable = false },
        on_attach = function(bufnr)
          local api = require("nvim-tree.api")
          -- default mappings
          api.config.mappings.default_on_attach(bufnr)
          -- single click to open files and folders
          vim.keymap.set("n", "<LeftRelease>", api.node.open.edit, { buffer = bufnr, noremap = true })
          -- remove Ctrl+T binding so it reaches toggleterm
          vim.keymap.del("n", "<C-t>", { buffer = bufnr })
        end,
        actions = {
          open_file = {
            quit_on_open = false,
            -- Never open files into the terminal window (which forces a split under it,
            -- inheriting the terminal's width). Excluding it sends files to a real editor
            -- window, or the picker if several are open.
            window_picker = {
              enable = true,
              exclude = {
                filetype = { "toggleterm" },
                buftype = { "terminal" },
              },
            },
          },
        },
      })

      vim.keymap.set("n", "<leader>e", "<cmd>NvimTreeToggle<cr>", { desc = "Toggle explorer" })
      vim.keymap.set("n", "<leader>v", "<cmd>NvimTreeFindFile<cr>", { desc = "Reveal file in explorer" })

      -- Link git status groups to semantic highlight groups so colours follow any theme.
      local function set_git_highlights()
        vim.api.nvim_set_hl(0, "NvimTreeGitDirtyIcon", { link = "DiagnosticWarn" })
        vim.api.nvim_set_hl(0, "NvimTreeGitNewIcon", { link = "Added" })
        vim.api.nvim_set_hl(0, "NvimTreeGitDeletedIcon", { link = "Removed" })
        vim.api.nvim_set_hl(0, "NvimTreeGitMergeIcon", { link = "DiagnosticError" })
        -- Colour only the glyph on folders, not the folder name.
        for _, kind in ipairs({ "Dirty", "Staged", "Deleted", "Ignored", "Merge", "New", "Renamed" }) do
          vim.api.nvim_set_hl(0, "NvimTreeGitFolder" .. kind .. "HL", { link = "NvimTreeFolderName" })
        end
      end
      vim.api.nvim_create_autocmd("ColorScheme", { callback = set_git_highlights })
      set_git_highlights()

      -- `nvim <dir>` (e.g. `nvim .`): open the tree as a side panel beside a real
      -- editor window, so there's always somewhere for files to open.
      vim.api.nvim_create_autocmd("VimEnter", {
        nested = true,
        callback = function(data)
          if vim.fn.argc() ~= 1 or vim.fn.isdirectory(data.file) ~= 1 then
            return
          end
          vim.cmd.cd(vim.fn.fnameescape(data.file))
          vim.cmd.enew() -- empty editor window
          local editor = vim.api.nvim_get_current_buf()
          pcall(vim.api.nvim_buf_delete, data.buf, { force = true }) -- drop the dir buffer
          require("nvim-tree.api").tree.open()
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(win) == editor then
              vim.api.nvim_set_current_win(win) -- leave focus in the editor
              break
            end
          end
        end,
      })
    end,
  },
}
