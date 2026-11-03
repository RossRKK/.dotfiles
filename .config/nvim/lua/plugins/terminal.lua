return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    ---@type snacks.Config
    opts = {
      -- terminal and lazygit are on-demand modules (no `enabled` needed). Add
      -- other snacks modules here as they get adopted.
    },
    config = function(_, opts)
      require("snacks").setup(opts)

      -- Normal mode only: terminal programs need <C-g> (Claude Code's edit in
      -- $EDITOR, fish's cancel), so from a terminal it's <C-n> first. A leader
      -- map can't serve -- <space> in a terminal would stutter waiting for it.
      -- <C-S-g> instead pops a project picker to drive a repo other than nvim's
      -- cwd (e.g. within a polyrepo tree).
      vim.keymap.set("n", "<C-g>", function()
        require("util.lazygit").open()
      end, { desc = "Open git TUI (lazygit)" })
      vim.keymap.set("n", "<C-S-g>", function()
        require("util.lazygit").pick()
      end, { desc = "Open git TUI in a picked project" })
      -- <leader>gP (PR for the current branch) lives in git.lua with the other
      -- <leader>g git maps.
    end,
  },
}
