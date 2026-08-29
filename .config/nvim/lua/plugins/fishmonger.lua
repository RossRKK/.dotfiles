-- fishmonger: the tmux-style side-terminal tab manager, split out as a local
-- plugin (dev = ~/dev, see config/lazy.lua). It's wired into the snacks terminal
-- in plugins/terminal.lua (setup + keymaps + the VimEnter auto-open), and edgy
-- (edgy.lua) governs its window via the "fishmonger" filetype.
return {
  {
    "RossRKK/fishmonger.nvim",
    dev = true,
    init = function()
      -- Bubble the whole nvim window's state up to the OS title, so the outer
      -- terminal's tab (Windows Terminal) summarises every workspace in here
      -- rather than only the one you are looking at: one segment per workspace
      -- tabpage, the project name prefixed with its side terminals' status
      -- glyphs (the symbol Claude Code prefixes its OSC title with, flipping
      -- while it thinks / waits for input), current workspace in brackets:
      --
      --   [✳✳ dotfiles] · nvim-config api
      --
      -- That way an agent waiting on you in a BACKGROUND workspace is visible
      -- from the emulator's tab strip without switching tabpages -- the job the
      -- per-tabpage bufferline label does inside nvim, one level up. Personal
      -- policy composed on fishmonger's FishmongerTabsChanged event, not part
      -- of the plugin.
      local function refresh_title()
        local fishmonger = package.loaded["fishmonger"]
        local workspace = require("config.workspace")
        local current = vim.api.nvim_get_current_tabpage()
        local segments = {}
        for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
          local icons = {}
          for _, term in ipairs(fishmonger and fishmonger.tabs(tab) or {}) do
            icons[#icons + 1] = fishmonger.title_icon(term.title)
          end
          local segment = workspace.name(tab)
          if #icons > 0 then
            segment = table.concat(icons) .. " " .. segment
          end
          segments[#segments + 1] = tab == current and ("[" .. segment .. "]") or segment
        end
        vim.o.title = true
        -- '%' is a statusline item in 'titlestring'; escape raw text.
        -- No "nvim" in it: the emulator tab is only ever this, so the name buys
        -- nothing and costs width that the workspace segments want.
        vim.o.titlestring = table.concat(segments, " "):gsub("%%", "%%%%")
      end

      -- Coalesced: the spinner tick raises FishmongerTabsChanged once per
      -- tabpage per frame, and refresh_title reads every tabpage anyway, so
      -- running it per event multiplied the work by the tab count several times
      -- a second. One deferred run per burst repaints the same title.
      local title_queued = false
      local function queue_title()
        if title_queued then
          return
        end
        title_queued = true
        vim.schedule(function()
          title_queued = false
          refresh_title()
        end)
      end

      -- A fresh branch report (config.greeter) has already repainted the tab
      -- labels itself; the OS title reads the same cache, so it repaints here.
      -- Without this a checkout only reached the title via unrelated events.
      vim.api.nvim_create_autocmd("User", {
        pattern = "GreeterReportChanged",
        callback = queue_title,
      })

      vim.api.nvim_create_autocmd("User", {
        pattern = "FishmongerTabsChanged",
        callback = function(ev)
          -- The event's own tabpage gets its bufferline label repainted (project
          -- name + glyphs, see config.workspace.set_label) -- that's how a
          -- background workspace surfaces "the agent here wants you" inside
          -- nvim. The title covers every tabpage, so background events repaint
          -- it too rather than returning early.
          require("config.workspace").set_label(ev.data.tab)
          queue_title()
        end,
      })

      -- The glyphs only move on the event above, but the segment LIST doesn't:
      -- which workspace is current, ones opening and closing, and a rename via
      -- :tcd are all invisible to fishmonger. Scheduled because at TabClosed /
      -- TabNewEntered time the tabpage list and cwd aren't settled yet.
      --
      -- The bufferline labels repaint here too: their glyph colours are baked
      -- against the tile's background (selected vs not, see
      -- config.workspace.set_label), so switching tabpages has to re-pick them
      -- even though no agent state moved.
      vim.api.nvim_create_autocmd(
        { "VimEnter", "TabEnter", "TabNewEntered", "TabClosed", "DirChanged" },
        {
          callback = vim.schedule_wrap(function()
            local workspace = require("config.workspace")
            for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
              workspace.set_label(tab)
            end
            refresh_title()
          end),
        }
      )
    end,
  },
}
