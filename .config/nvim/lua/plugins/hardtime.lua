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
    keys = {
      {
        "<leader>up",
        function()
          local hardtime = require("hardtime")
          local presenting = require("util.presenting")
          Snacks.toggle
            .new({
              id = "presenting",
              name = "Presenting (no hardtime, mouse on)",
              get = function()
                return presenting.is_on(hardtime)
              end,
              set = function(on)
                presenting.set(hardtime, on)
              end,
            })
            :toggle()
        end,
        desc = "Toggle presenting (hardtime off, mouse on)",
      },
    },
  },
}
