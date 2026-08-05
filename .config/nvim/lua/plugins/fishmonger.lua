-- fishmonger: the tmux-style side-terminal tab manager, split out as a local
-- plugin (dev = ~/dev, see config/lazy.lua). It's wired into the snacks terminal
-- in plugins/terminal.lua (setup + keymaps + the VimEnter auto-open), and edgy
-- (edgy.lua) governs its window via the "fishmonger" filetype.
return {
  {
    "RossRKK/fishmonger.nvim",
    dev = true,
    init = function()
      -- Bubble each tab's status glyph (the symbol Claude Code prefixes its
      -- OSC title with, flipping while it thinks / waits for input) up to the
      -- OS window title, so the outer terminal's tab (Windows Terminal) shows
      -- every fishmonger tab's state at a glance: "✳✳· nvim <cwd>". Personal
      -- policy composed on fishmonger's FishmongerTabsChanged event, not part
      -- of the plugin. Once a title has been written we keep owning it —
      -- releasing 'title' would just strand the last string in the emulator —
      -- so with no icons we still render the plain tail.
      local owned = false
      vim.api.nvim_create_autocmd("User", {
        pattern = "FishmongerTabsChanged",
        callback = function(ev)
          local icons = {}
          for _, tab in ipairs(ev.data.tabs) do
            icons[#icons + 1] = require("fishmonger").title_icon(tab.title)
          end
          if #icons == 0 and not owned then
            return
          end
          owned = true
          local tail = "nvim " .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
          local text = #icons > 0 and (table.concat(icons) .. " " .. tail) or tail
          vim.o.title = true
          -- '%' is a statusline item in 'titlestring'; escape raw text.
          vim.o.titlestring = text:gsub("%%", "%%%%")
        end,
      })
    end,
  },
}
