-- Fuzzy finder (snacks picker), replacing telescope. Configured as a second
-- fragment of the snacks.nvim spec -- lazy merges these opts into the ones in
-- terminal.lua, and require("snacks").setup there enables the picker at startup.
--
-- Enabling the picker also points vim.ui.select at Snacks.picker (ui_select is on
-- by default), so the review-mode selection prompts in lua/review/ get the snacks
-- UI without any extra wiring.
--
-- LSP navigation pickers (gd/gi/gr) live in lua/plugins/lsp.lua (they attach
-- per-buffer on LspAttach). TODO search is TodoTrouble; see todo-comments.lua.

return {
  "folke/snacks.nvim",
  ---@type snacks.Config
  opts = {
    picker = {
      enabled = true,
      -- Default preset: horizontal, input on top, preview on the right -- matches
      -- the old telescope layout (horizontal + prompt_position=top). The snacks
      -- "telescope" preset instead puts the prompt at the bottom.
      layout = { preset = "default" },
    },
  },
  keys = {
    { "<C-p>", function() Snacks.picker.files() end, desc = "Find files" },
    { "<leader>fg", function() Snacks.picker.grep() end, desc = "Live grep" },
    {
      "<leader>fd",
      function() Snacks.picker.grep({ dirs = { vim.fn.expand("%:p:h") } }) end,
      desc = "Live grep in current file's dir",
    },
    { "<leader>fb", function() Snacks.picker.buffers() end, desc = "Find buffers" },
    { "<leader>fh", function() Snacks.picker.help() end, desc = "Help tags" },
    -- LSP symbol search (candidates are symbols, not text lines). fs: current
    -- file (VS Code "Go to Symbol"); fw: whole workspace, re-queried live.
    { "<leader>fs", function() Snacks.picker.lsp_symbols() end, desc = "Document symbols" },
    {
      "<leader>fw",
      function() Snacks.picker.lsp_workspace_symbols() end,
      desc = "Workspace symbols",
    },
  },
}
