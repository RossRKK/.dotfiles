-- Session restore, TEMPORARILY DISABLED while workspaces (one project per
-- tabpage, see config/workspace.lua) settle.
--
-- The two don't compose as-is: persistence saves one session per cwd, and
-- 'sessionoptions' carries a single `curdir`. With several project tabpages open
-- in one nvim there is no single cwd to save, and restoring would drop one
-- project's files into whichever tab happened to be current. Startup therefore
-- opens an empty editor window rather than reopening the last files.
--
-- Re-enabling needs a per-tabpage answer (save/restore a tab's cwd + buffers as
-- a unit), not just flipping `enabled` back.
return {
  {
    "folke/persistence.nvim",
    enabled = false,
  },
}
