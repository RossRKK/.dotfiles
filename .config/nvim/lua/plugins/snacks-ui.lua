-- Extra snacks modules layered onto the base spec in terminal.lua (lazy merges
-- these opts into the ones there, and require("snacks").setup applies them).
--
-- - notifier: replaces the native vim.notify with a toast UI + scrollback history.
-- - scope: indent/treesitter scope text objects (ii/ai select the current scope).
-- - quickfile: renders a file passed on the command line before the rest of the
--   plugins load -- the text-editor-mode path (`nvim somefile`), where startup
--   latency is most visible.
-- - gh pickers: browse GitHub issues / PRs via the gh CLI (already authed).
-- - scratch: persistent scratch buffers, keyed per project + filetype, in a
--   floating window. `<leader>.` toggles the default one; `<leader>S` picks
--   among all of them (including other projects').

return {
  "folke/snacks.nvim",
  ---@type snacks.Config
  opts = {
    -- Replaces the native cmdline vim.ui.input with a floating input (used by
    -- e.g. <leader>tf's branch-name prompt, LSP rename).
    input = { enabled = true },
    notifier = { enabled = true },
    quickfile = { enabled = true },
    -- Default keys: ii/ai select the current scope; [i / ]i jump to its top /
    -- bottom edge. The jumps shadow the [i / ]i builtins (echo the first line
    -- containing the keyword under the cursor) -- an accepted trade-off here.
    scope = { enabled = true },
    scratch = { enabled = true },
  },
  keys = {
    -- Toggle scratch buffer. Mapped in terminal mode too, so it works from the
    -- side terminal -- which rules out <leader>: a terminal-mode <Space>
    -- mapping would make every space wait out timeoutlen before reaching the
    -- shell. Ctrl+/ is one of the few Ctrl+punctuation chords with a legacy
    -- terminal encoding (it arrives as <C-_>); Ctrl+. only exists under the
    -- kitty keyboard protocol, which Windows Terminal doesn't speak. Both
    -- spellings are mapped so it also works in CSI-u terminals like ghostty.
    {
      "<C-/>",
      function()
        Snacks.scratch()
      end,
      mode = { "n", "t" },
      desc = "Toggle scratch buffer",
    },
    {
      "<C-_>",
      function()
        Snacks.scratch()
      end,
      mode = { "n", "t" },
      desc = "Toggle scratch buffer",
    },
    {
      "<leader>S",
      function()
        Snacks.scratch.select()
      end,
      desc = "Select scratch buffer",
    },
    {
      "<leader>n",
      function()
        Snacks.notifier.show_history()
      end,
      desc = "Notification history",
    },
    {
      "<leader>ghi",
      function()
        Snacks.picker.gh_issue()
      end,
      desc = "GitHub issues",
    },
    {
      "<leader>ghp",
      function()
        Snacks.picker.gh_pr()
      end,
      desc = "GitHub PRs",
    },
  },
}
