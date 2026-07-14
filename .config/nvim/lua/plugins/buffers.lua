return {
  {
    -- Buffer "garbage collection": auto-close buffers left untouched for a while
    -- so hidden buffers stop piling up. Never closes unsaved or currently-visible
    -- buffers (plugin defaults), so it only reaps genuinely-idle ones.
    "chrisgrieser/nvim-early-retirement",
    event = "VeryLazy",
    opts = {
      retirementAgeMins = 20,
      -- Keep a few around even if idle, so cycling with <S-l>/<S-h> isn't empty.
      minimumBufferNum = 4,
      -- Don't retire special/tool buffers.
      ignoredFiletypes = { "snacks_terminal", "neo-tree", "gitcommit", "help", "qf" },
      -- A brief notice when one is closed, so the behaviour isn't invisible.
      notificationOnAutoClose = true,
    },
  },
}
