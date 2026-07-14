-- Visualise and time-travel the undo *tree* -- Vim keeps undo as a branching
-- tree, not a line, so edits you undo-then-type-over are still reachable here.
-- Persistent undo (opt.undofile in config/options.lua) makes the tree survive
-- restarts.
return {
  {
    "mbbill/undotree",
    keys = {
      { "<leader>u", "<cmd>UndotreeToggle<cr>", desc = "Toggle undo tree" },
    },
    config = function()
      vim.g.undotree_SetFocusWhenToggle = 1 -- jump into the panel on open
    end,
  },
}
