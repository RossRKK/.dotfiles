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
      vim.keymap.set("n", "<leader>g", "<cmd>NvimTreeFindFile<cr>", { desc = "Reveal file in explorer" })
    end,
  },
}
