-- Live-previewing LSP rename. `:IncRename <new>` issues the same
-- textDocument/rename the builtin does, but as a command with a preview
-- callback, so `inccommand` paints every occurrence as you type and <Esc>
-- aborts before anything is written.
--
-- The mapping is <leader>rn, set buffer-locally on LspAttach in plugins/lsp.lua
-- (only servers that support rename get it) -- not here, so there's one place
-- that owns the LSP keymaps.
return {
  {
    "smjonas/inc-rename.nvim",
    -- Not `cmd = "IncRename"`: lazy's command stub carries no preview callback,
    -- so `inccommand` has nothing to run and the first rename of a session is
    -- previewless (the plugin only loads once you hit <CR>). LspAttach is the
    -- same event that creates the <leader>rn mapping, so the real command --
    -- the one defined with `preview =` -- exists as soon as the key does.
    event = "LspAttach",
    -- Needs `inccommand` set to see the preview; options.lua uses "split", which
    -- additionally lists every changed line across the project in the preview
    -- window.
    opts = {},
  },
}
