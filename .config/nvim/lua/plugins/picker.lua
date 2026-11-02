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

-- Snacks only opens over file windows, and with none it takes any split (the
-- side panel, say); a <C-b>t terminal as the main window should be the target.
local function target_main_window(picker)
  local windows = require("config.windows")
  if not windows.is_editor_window(picker.main) then
    picker.main = windows.main_window() or picker.main
  end
end

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
      -- Open in normal mode in the query: j/k/gg/G/q/<CR> still drive the list,
      -- and `p` pastes a copied name. Snacks enters insert on the input's
      -- BufEnter in the same tick as on_show, so the stopinsert is scheduled.
      on_show = function(picker)
        target_main_window(picker)
        vim.schedule(vim.cmd.stopinsert)
      end,
      -- Live grep lists nothing until you type, so it stays in insert.
      sources = { grep = { on_show = target_main_window } },
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
    -- fo = :oldfiles, the dashboard's "Recent file" entry reachable once you've
    -- left the dashboard. Wider than fb: files closed (or from a past session).
    { "<leader>fo", function() Snacks.picker.recent() end, desc = "Recent files" },
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
