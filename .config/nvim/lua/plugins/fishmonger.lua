-- fishmonger: the tmux-style side-terminal tab manager, split out as a local
-- plugin (dev = ~/dev, see config/lazy.lua). It's wired into the snacks terminal
-- in plugins/terminal.lua (setup + keymaps + the VimEnter auto-open), and edgy
-- (edgy.lua) governs its window via the "fishmonger" filetype.
return {
  { "RossRKK/fishmonger.nvim", dev = true },
}
