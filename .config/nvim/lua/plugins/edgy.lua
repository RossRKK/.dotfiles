-- Window layout manager. edgy pins panels to the screen edges and owns their
-- placement and sizing, replacing the hand-rolled width math (ide.term_width),
-- the WinResized enforcer, and the manual outline-stacking splits.
--
-- Layout: explorer + outline on the LEFT, the side terminal on the RIGHT, the
-- editor in the middle. The terminal's tmux-style tab manager (config/terms.lua)
-- is unchanged -- it only ever shows one terminal window at a time, which edgy
-- just positions in the right edgebar.

return {
  {
    "folke/edgy.nvim",
    -- Load at startup (not VeryLazy): IDE mode auto-opens the explorer + terminal
    -- at VimEnter, which fires before VeryLazy, so edgy must have its window hooks
    -- registered first or those panels open unmanaged.
    lazy = false,
    priority = 900, -- after snacks (1000), before the VimEnter auto-opens
    init = function()
      -- edgy needs the global statusline (panels can only fully collapse with it),
      -- and splitkeep=screen stops the middle splits jumping when an edge opens.
      vim.opt.laststatus = 3
      vim.opt.splitkeep = "screen"
    end,
    ---@type Edgy.Config
    opts = {
      -- Default minimum sizes for each edge; individual views can override.
      options = {
        left = { size = 35 },
        right = { size = 0.4 }, -- ~40% width, biased toward the code like before
      },
      left = {
        -- The file tree, taking most of the column height. git_status shares this
        -- slot: <leader>gt swaps the filesystem source for git_status in place
        -- (neo-tree reuses the window), so both belong to the same edgy view.
        {
          title = "Explorer",
          ft = "neo-tree",
          filter = function(buf)
            local src = vim.b[buf].neo_tree_source
            return src == "filesystem" or src == "git_status"
          end,
          size = { height = 0.7 },
        },
        -- The symbols outline stacks beneath the tree. neo-tree replaces a second
        -- same-position source, so explorer.lua opens this one elsewhere and edgy
        -- relocates it here -- which is exactly what removes the old split hack.
        {
          title = "Outline",
          ft = "neo-tree",
          filter = function(buf)
            return vim.b[buf].neo_tree_source == "document_symbols"
          end,
          size = { height = 0.3 },
        },
      },
      right = {
        -- The snacks side terminal. Exclude floats so lazygit (a float) is never
        -- pulled into the edgebar. winbar=false suppresses edgy's title bar here:
        -- config/terms.lua already draws the tmux-style tab strip over this region
        -- in the top tabline, so an edgy title would just duplicate it.
        {
          ft = "snacks_terminal",
          title = "Terminal",
          filter = function(_, win)
            return vim.api.nvim_win_get_config(win).relative == ""
          end,
          wo = { winbar = false },
        },
      },
    },
  },
}
