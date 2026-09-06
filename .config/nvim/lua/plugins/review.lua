-- Branch review mode, split across two local plugins (dev = ~/dev, see
-- config/lazy.lua). The coupling lives here -- it's config, not baked into
-- either plugin:
--   * triage.nvim  owns the per-file review status, the gitsigns base, and the
--     explorer status glyph.
--   * nitpick.nvim owns inline GitHub PR comments + drafts.
-- The one review-mode toggle drives both (triage's on_toggle -> nitpick.set_shown),
-- and nitpick borrows triage's verdict as its submit event.
--
-- neo-tree renders their glyphs (triage_status / nitpick_marker components) --
-- registered in plugins/explorer.lua, which requires the adapters directly and
-- so pulls both plugins in at startup alongside the tree.
return {
  {
    "RossRKK/triage.nvim",
    dev = true,
    config = function()
      require("triage").setup({
        -- Review mode is per repo, so the toggle carries the root it applies
        -- to: with one project per tab, both plugins must follow the SAME repo
        -- rather than each resolving the cwd's on its own.
        on_toggle = function(on, root)
          require("nitpick").set_shown(on, root)
        end,
      })
    end,
  },
  {
    "RossRKK/nitpick.nvim",
    dev = true,
    config = function()
      require("nitpick").setup({ verdict = require("triage").verdict })
    end,
  },
}
