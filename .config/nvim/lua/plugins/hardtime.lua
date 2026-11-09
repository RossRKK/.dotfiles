-- Nudges away from hjkl/arrow repetition toward real motions: past max_count it
-- says what to use instead; :Hardtime report lists habits.
return {
  {
    "m4xshen/hardtime.nvim",
    lazy = false,
    dependencies = { "MunifTanjim/nui.nvim" },
    opts = {
      -- Hint rather than swallow the key: the nudge without the lockout.
      restriction_mode = "hint",
      -- <leader>um owns the mouse; hardtime shouldn't fight it.
      disable_mouse = false,
    },
    keys = {
      {
        "<leader>up",
        function()
          local hardtime = require("hardtime")
          Snacks.toggle
            .new({
              id = "hardtime",
              name = "Hardtime",
              get = function()
                return hardtime.is_plugin_enabled
              end,
              set = function(on)
                if on then
                  hardtime.enable()
                else
                  hardtime.disable()
                end
              end,
            })
            :toggle()
        end,
        desc = "Toggle hardtime",
      },
    },
  },
}
