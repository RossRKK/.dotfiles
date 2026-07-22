-- Window layout manager. edgy pins panels to the screen edges and owns their
-- placement and sizing, replacing the hand-rolled width math (ide.term_width),
-- the WinResized enforcer, and the manual outline-stacking splits.
--
-- Layout: explorer + outline on the LEFT, the side terminal on the RIGHT, the
-- editor in the middle. The terminal's tmux-style tab manager (fishmonger)
-- is unchanged -- it only ever shows one terminal window at a time, which edgy
-- just positions in the right edgebar.

-- edgy re-applies each panel's `size` on every layout, so a plain fraction
-- snaps the panel back after any manual resize. live_size instead reports the
-- window's CURRENT size, so edgy's re-apply is a no-op and drags stick.
--
-- The catch: a freshly opened window is briefly parked at a transient size
-- (edgy rebuilds the splits before proportioning them), and latching that would
-- wedge the panel near-empty. So for the first WARMUP_MS of a given window's
-- life we hand back the opening size and let edgy proportion the panel; only
-- after that do we start tracking the live size. Two live
-- siblings sharing a column (explorer/outline) must BOTH use this -- pairing a
-- live panel with an auto-sized one is asymmetric and collapses the live one.
local WARMUP_MS = 1000

-- Birth tick per panel window id (shared across panels); cleared on reset so
-- panels re-warm to their opening sizes.
local births = {}

local function find_win(predicate)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    -- Skip floats (relative ~= ""): lazygit etc. must never be mistaken for the
    -- panel window whose size we track.
    if vim.api.nvim_win_get_config(win).relative == "" then
      if predicate(vim.api.nvim_win_get_buf(win)) then
        return win
      end
    end
  end
end

-- Reset callbacks, one per live_size panel; :EdgyResetSizes / the keymap below
-- clear every panel back to its opening size.
local resets = {}

---@param initial number opening size (fraction < 1, or absolute columns/lines)
---@param dim "width" | "height"
---@param predicate fun(buf: integer): boolean identifies the panel's buffer
local function live_size(initial, dim, predicate)
  local size ---@type number?
  table.insert(resets, function()
    size = nil
  end)
  return function()
    local win = find_win(predicate)
    if not win then
      return size or initial
    end
    local now = (vim.uv or vim.loop).now()
    births[win] = births[win] or now
    -- Warm-up window: let edgy proportion the panel from the opening size before
    -- we start latching, so a startup/open transient can't wedge it.
    if now - births[win] < WARMUP_MS then
      return initial
    end
    local live = vim.api["nvim_win_get_" .. dim](win)
    if live > 1 then -- ignore edgy's collapsed 1-line/col parking size
      size = live
    end
    return size or initial
  end
end

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
  for win in pairs(births) do
    births[win] = nil
  end
  for _, reset in ipairs(resets) do
    reset()
  end
  require("edgy.layout").update()
end

local function is_terminal(buf)
  return vim.bo[buf].filetype == "fishmonger"
end

local function is_explorer(buf)
  local src = vim.b[buf].neo_tree_source
  return src == "filesystem" or src == "git_status"
end

local function is_outline(buf)
  return vim.b[buf].neo_tree_source == "document_symbols"
end

-- Any window in the left column (explorer or outline); they share one width.
local function is_left(buf)
  return vim.bo[buf].filetype == "neo-tree"
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
      require("edgy").setup(opts)
      vim.api.nvim_create_user_command("EdgyResetSizes", reset_sizes, {
        desc = "Reset edgy panel sizes to their opening fractions",
      })
      vim.keymap.set("n", "<leader>wr", reset_sizes, { desc = "Reset edgy panel sizes" })
    end,
    ---@type Edgy.Config
    opts = {
      -- Arrow-key resizing for edge windows. Plain :resize (not edgy's
      -- win:resize) so it flows through the same live_size tracking as a mouse
      -- drag -- win:resize stores its own width and would re-introduce a floor
      -- that blocks shrinking. Convention: Right/Up grow, Left/Down shrink.
      keys = {
        ["<C-Right>"] = function(win)
          vim.api.nvim_win_call(win.win, function() vim.cmd("vertical resize +2") end)
        end,
        ["<C-Left>"] = function(win)
          vim.api.nvim_win_call(win.win, function() vim.cmd("vertical resize -2") end)
        end,
        ["<C-Up>"] = function(win)
          vim.api.nvim_win_call(win.win, function() vim.cmd("resize +2") end)
        end,
        ["<C-Down>"] = function(win)
          vim.api.nvim_win_call(win.win, function() vim.cmd("resize -2") end)
        end,
      },
      options = {
        -- Open at 35 cols, then follow resizes. Live-tracking (not a constant)
        -- is what lets neo-tree's `e` (toggle_auto_expand_width) stick instead
        -- of fighting winfixwidth -- see explorer.lua.
        left = { size = live_size(35, "width", is_left) },
        -- Open at ~40% width, then follow whatever the user resizes it to.
        right = { size = live_size(0.4, "width", is_terminal) },
      },
      left = {
        -- The file tree, ~70% of the column. It must live-track too: pairing a
        -- live outline with an auto-sized explorer is asymmetric and collapses
        -- the outline on open, whereas two live siblings share the column and
        -- stay put when either is dragged. git_status shares this slot:
        -- <leader>gt swaps the filesystem source for git_status in place
        -- (neo-tree reuses the window), so both belong to the same edgy view.
        {
          title = "Explorer",
          ft = "neo-tree",
          filter = is_explorer,
          size = { height = live_size(0.7, "height", is_explorer) },
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
          -- Opens at ~30% height, then follows manual resizes (see live_size).
          size = { height = live_size(0.3, "height", is_outline) },
        },
      },
      right = {
        -- The fishmonger side terminal. Exclude floats so lazygit (a float) is
        -- never pulled into the edgebar. No `title`/`winbar` here: fishmonger
        -- draws its own tmux-style tab strip as the window's winbar and
        -- re-asserts it after each buffer swap (edgy blanks a panel's winbar on
        -- swap), so edgy only needs to adopt and size this window.
        {
          ft = "fishmonger",
          filter = function(_, win)
            return vim.api.nvim_win_get_config(win).relative == ""
          end,
        },
      },
    },
  },
}
