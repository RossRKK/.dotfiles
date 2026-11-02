-- Nudges away from hjkl/arrow repetition toward real motions. Hint mode: it
-- suggests rather than blocks, and :Hardtime report lists the habits it saw.
return {
  {
    "m4xshen/hardtime.nvim",
    lazy = false,
    dependencies = { "MunifTanjim/nui.nvim" },
    opts = {
      restriction_mode = "hint",
      -- The mouse is off in options.lua; hardtime shouldn't own it as well.
      disable_mouse = false,
    },
  },
}
