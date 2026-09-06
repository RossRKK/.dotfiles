-- Window layout manager. edgy pins panels to the screen edges and owns their
-- placement and sizing, replacing the hand-rolled width math (ide.term_width),
-- the WinResized enforcer, and the manual outline-stacking splits.
--
-- Layout: the explorer on the LEFT, the side terminal on the RIGHT, the
-- editor in the middle. The terminal's tmux-style tab manager (fishmonger)
-- is unchanged -- it only ever shows one terminal window at a time, which edgy
-- just positions in the right edgebar.

-- Manual resizes (drag, :resize, neo-tree auto-expand) are written into edgy's
-- per-window size override by util/edgy_pin.lua, so they stick instead of
-- snapping back to the view's opening size.
local edgy_pin = require("util.edgy_pin")

local function reset_sizes()
  -- Turn off neo-tree's auto-expand-width first: otherwise it keeps widening the
  -- panel to fit the longest name and fights the width we're resetting to.
  local mgr = require("neo-tree.sources.manager")
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neo-tree" then
      local state = mgr.get_state_for_window(win)
      if state and state.window then
        state.window.auto_expand_width = false
      end
    end
  end
  edgy_pin.reset()
end

local function is_explorer(buf)
  local src = vim.b[buf].neo_tree_source
  return src == "filesystem" or src == "git_status"
end

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
    config = function(_, opts)
      -- Before edgy's setup: its WinResized handler must run after ours.
      edgy_pin.setup()
      require("edgy").setup(opts)
      vim.api.nvim_create_user_command("EdgyResetSizes", reset_sizes, {
        desc = "Reset edgy panel sizes to their opening sizes",
      })
      vim.keymap.set("n", "<leader>wr", reset_sizes, { desc = "Reset edgy panel sizes" })
    end,
    ---@type Edgy.Config
    opts = {
      -- Panels snap to size. The glide is distracting, and every frame of it is
      -- a resize that edgy_pin has to recognise and ignore.
      animate = { enabled = false },
      -- Arrow-key resizing for edge windows, through edgy's own resize so the
      -- new size lands straight in its override. Right/Up grow, Left/Down shrink.
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
      options = {
        -- These are MINIMUMS, not opening sizes: edgy sizes a bar as
        -- max(this, each window's override or view size). Opening sizes sit on
        -- the views below; these just stop a panel being dragged to nothing.
        left = { size = 10 },
        right = { size = 10 },
      },
      left = {
        -- The file tree, sole occupant of the column (the symbols outline is a
        -- float now, see plugins/explorer.lua), so it needs no height of its
        -- own -- only the column width below. git_status shares this slot:
        -- <leader>gt swaps the filesystem source for git_status in place
        -- (neo-tree reuses the window), so both belong to the same edgy view.
        {
          title = "Explorer",
          ft = "neo-tree",
          filter = is_explorer,
          -- Opening width; neo-tree's `e` (toggle_auto_expand_width) and drags
          -- then override it via edgy_pin -- see explorer.lua.
          size = { width = 35 },
        },
      },
      right = {
        -- The fishmonger side terminal. Exclude floats so lazygit (a float) is
        -- never pulled into the edgebar. fishmonger draws its own tmux-style tab
        -- strip as the window's winbar, so edgy only needs to adopt and size
        -- this window.
        --
        -- `winbar = false` is load-bearing: it's the one value that makes edgy
        -- leave the option alone (true installs edgy's own titlebar expression,
        -- and edgy's default is true). Without it, every Edgy.Window construction
        -- for this window overwrites fishmonger's winbar with edgy's -- which,
        -- for a view with no title, renders as an empty strip. That construction
        -- is not once-per-window: edgy caches Edgy.Window objects in a
        -- WEAK-VALUED table keyed by window handle, so a garbage collection drops
        -- the entry and the next layout update rebuilds it and re-applies `wo`.
        -- Hence the tab strip vanishing at unpredictable moments rather than on
        -- any one action.
        {
          ft = "fishmonger",
          wo = { winbar = false },
          size = { width = 0.4 }, -- opening width, ~40% of the screen
          filter = function(_, win)
            return vim.api.nvim_win_get_config(win).relative == ""
          end,
        },
      },
    },
  },
}
