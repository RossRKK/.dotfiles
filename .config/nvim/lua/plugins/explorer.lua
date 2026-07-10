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
          -- Append the branch-review decorator after the builtins so its
          -- ●/✓ indicators sit at the end of the row.
          decorators = {
            "Git",
            "Open",
            "Hidden",
            "Modified",
            "Bookmark",
            "Diagnostics",
            "Copied",
            require("review.decorator"),
            "Cut",
          },
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
          -- single click to open files and folders, but never navigate up a
          -- level: clicking the root folder row normally changes the root to
          -- the parent dir, which we never want.
          local function click_open()
            local node = api.tree.get_node_under_cursor()
            if not node or node.name == ".." then
              return
            end
            api.node.open.edit()
          end
          vim.keymap.set("n", "<LeftRelease>", click_open, { buffer = bufnr, noremap = true })
          -- Double-click defaults to the raw open action, which on the ".." root
          -- row navigates up a level -- guard it the same way.
          vim.keymap.set("n", "<2-LeftMouse>", click_open, { buffer = bufnr, noremap = true })
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
      -- focus=false reveals the file in the tree but keeps the cursor in the
      -- editor -- this is normally just for context. (The :NvimTreeFindFile
      -- command has no such option and always jumps to the tree.)
      vim.keymap.set("n", "<leader>v", function()
        require("nvim-tree.api").tree.find_file({ open = true, focus = false })
      end, { desc = "Reveal file in explorer (keep focus)" })

      -- Link git status groups to semantic highlight groups so colours follow any theme.
      local function set_git_highlights()
        vim.api.nvim_set_hl(0, "NvimTreeGitDirtyIcon", { link = "DiagnosticWarn" })
        vim.api.nvim_set_hl(0, "NvimTreeGitNewIcon", { link = "Added" })
        vim.api.nvim_set_hl(0, "NvimTreeGitDeletedIcon", { link = "Removed" })
        vim.api.nvim_set_hl(0, "NvimTreeGitMergeIcon", { link = "DiagnosticError" })
        -- Colour only the glyph on folders, not the folder name.
        for _, kind in ipairs({ "Dirty", "Staged", "Deleted", "Ignored", "Merge", "New", "Renamed" }) do
          vim.api.nvim_set_hl(
            0,
            "NvimTreeGitFolder" .. kind .. "HL",
            { link = "NvimTreeFolderName" }
          )
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
          pcall(vim.api.nvim_buf_delete, data.buf, { force = true }) -- drop the dir buffer
          pcall(require("persistence").load) -- reopen this dir's files (no-op if none saved)
          local editor = vim.api.nvim_get_current_win()
          require("nvim-tree.api").tree.open()
          vim.api.nvim_set_current_win(editor) -- leave focus in the editor
        end,
      })

      -- Branch review mode: commands, keymaps, gitsigns base, explorer colours.
      require("review").setup()
    end,
  },
}
