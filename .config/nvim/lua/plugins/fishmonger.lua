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
          -- The event's own tabpage gets its bufferline label repainted (project
          -- name + glyphs, see config.workspace.set_label) -- that's how a
          -- background workspace surfaces "the agent here wants you".
          require("config.workspace").set_label(ev.data.tab)

          -- The OS title stays a report on the workspace you're IN, so the
          -- terminal emulator's own tab keeps meaning "this window, right now".
          -- Events from a background tabpage therefore only repaint the label
          -- above; ev.data.tabs would be that other project's terminals.
          if ev.data.tab ~= vim.api.nvim_get_current_tabpage() then
            return
          end
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
