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
      -- Arrow-key resizing for edge windows, on top of edgy's own <C-w></>/+/-.
      -- These merge into edgy's default keys (deep-extend), so both sets work;
      -- edgy's win:resize sticks against winfixwidth where :resize wouldn't.
      -- Convention: Right/Up grow, Left/Down shrink.
      keys = {
        ["<C-Right>"] = function(win)
          win:resize("width", 2)
        end,
        ["<C-Left>"] = function(win)
          win:resize("width", -2)
        end,
        ["<C-Up>"] = function(win)
          win:resize("height", 2)
        end,
        ["<C-Down>"] = function(win)
          win:resize("height", -2)
        end,
      },
      -- Default minimum sizes for each edge; individual views can override.
      options = {
        left = { size = 35 },
        -- ~40% width, biased toward the code -- but never below 80 columns, so the
        -- terminal always fits a standard 80-col line. edgy re-runs this on every
        -- VimResized; returning an absolute count (>= 1) overrides the fraction path.
        -- The 40% floor only yields below 80 under ~200 total columns, where the
        -- editor gives up the difference instead.
        right = { size = function()
          return math.max(80, math.floor(vim.o.columns * 0.4))
        end },
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
