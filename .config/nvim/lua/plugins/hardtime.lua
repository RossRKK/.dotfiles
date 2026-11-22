-- Nudges away from hjkl/arrow repetition toward real motions: past max_count it
-- says what to use instead; :Hardtime report lists habits.

--- Wraps hardtime's insert-mode arrow maps so they move through the builtin completion menu
--- (agentic's prompt completes with it); outside a menu hardtime still disables them.
local function let_arrows_into_menus()
  for _, key in ipairs({ "<Up>", "<Down>" }) do
    local disabled = vim.fn.maparg(key, "i", false, true).callback
    if disabled then
      vim.keymap.set("i", key, function()
        return vim.fn.pumvisible() == 1 and key or disabled()
      end, { expr = true, desc = "which_key_ignore" })
    end
  end
end

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
    config = function(_, opts)
      local hardtime = require("hardtime")
      local enable = hardtime.enable
      -- hardtime has no hook for this; every enable path (deferred setup, :Hardtime, the toggle) goes through M.enable.
      hardtime.enable = function()
        local was_enabled = hardtime.is_plugin_enabled
        enable()
        if not was_enabled then
          let_arrows_into_menus()
        end
      end
      hardtime.setup(opts)
    end,
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
