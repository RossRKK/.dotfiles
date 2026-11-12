-- Markdown todo lists: renders `- [ ]` as checkboxes and toggles them in place,
-- while the file on disk stays plain GFM that agents can edit too. Activates on
-- its default file names (todo.md and friends), which ~/notes/todo.md matches;
-- the greeter lists that file's open items (config/greeter.lua).
--
-- Its <leader>T keys are buffer-local to todo files, so they shadow neotest's
-- <leader>T only where there is no test to run.
return {
  {
    "bngarren/checkmate.nvim",
    ft = "markdown",
    opts = {},
  },
}
