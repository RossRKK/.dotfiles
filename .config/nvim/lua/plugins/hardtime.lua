-- Nudges away from hjkl/arrow repetition toward real motions: past max_count it
-- swallows the key and says what to use instead; :Hardtime report lists habits.
return {
  {
    "m4xshen/hardtime.nvim",
    lazy = false,
    dependencies = { "MunifTanjim/nui.nvim" },
    opts = {
      -- The mouse is off in options.lua; hardtime shouldn't own it as well.
      disable_mouse = false,
    },
  },
}
