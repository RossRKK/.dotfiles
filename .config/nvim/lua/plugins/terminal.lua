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

      -- <C-g> works from normal and terminal mode (pairs with the <C-t>
      -- side-terminal toggle) so the git TUI is reachable wherever the cursor
      -- is; a second press hides it. A leader map can't serve here -- <space>
      -- in a terminal would stutter waiting for the chord, breaking legitimate
      -- space presses -- so the git TUI stays on a ctrl key.
      -- <C-S-g> instead pops a project picker to drive a repo other than nvim's
      -- cwd (e.g. within a polyrepo tree).
      vim.keymap.set({ "n", "t" }, "<C-g>", function()
        require("util.lazygit").open()
      end, { desc = "Open git TUI (lazygit)" })
      vim.keymap.set({ "n", "t" }, "<C-S-g>", function()
        require("util.lazygit").pick()
      end, { desc = "Open git TUI in a picked project" })
      -- <leader>gP (PR for the current branch) lives in git.lua with the other
      -- <leader>g git maps.
    end,
  },
}
