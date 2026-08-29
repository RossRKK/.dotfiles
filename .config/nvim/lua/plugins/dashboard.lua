-- Greeter for bare `nvim` (snacks.dashboard), as a further fragment of the
-- snacks spec in terminal.lua.
--
-- Bare `nvim` is text-editor mode (see config/ide.lua): nothing auto-opens, and
-- until now that meant an empty buffer with no route to a project. The dashboard
-- fills that gap with the two workspace entry points (<leader>tn recent projects,
-- <leader>te browse) plus plain file finding, so opening a project is a keypress from
-- startup rather than something you have to remember the mapping for.
--
-- snacks shows it only when nvim starts with no file arguments and no stdin, so
-- `nvim <dir>` (IDE mode, handled by the VimEnter handler in explorer.lua) and
-- `nvim <file>` are untouched -- as are commit-message and edit-prompt invocations.
--
-- The workspace actions run with `tab = false` and drop the dashboard buffer:
-- the greeter occupies the tabpage nvim started in, so that tab should BECOME the
-- workspace. Opening a new tabpage instead would leave an empty dashboard tab
-- behind as tab 1 forever.

---@param fn fun(opts: table)
---@return fun()
local function into_this_tab(fn)
  return function()
    fn({ drop_buf = vim.api.nvim_get_current_buf() })
  end
end

return {
  "folke/snacks.nvim",
  ---@type snacks.Config
  opts = {
    dashboard = {
      enabled = true,
      sections = {
        { section = "header" },
        { section = "keys", gap = 1, padding = 1 },
        -- The projects list is snacks' own: the git roots of your recent files
        -- (:oldfiles / shada) -- editing history, not shell-cd history. Same idea as
        -- <leader>tn (config/workspace.lua), which uses the picker over that source.
        --
        -- Its default action chdirs and then opens a file picker; ours builds the
        -- full IDE layout on that directory instead, exactly as `nvim <dir>` does.
        -- The `action` sits on a CHILD entry rather than on the titled section:
        -- dashboard moves a titled section's own action onto the title row and
        -- then clears it, which would leave the project rows back on the default.
        {
          icon = " ",
          title = "Projects",
          indent = 2,
          padding = 1,
          {
            section = "projects",
            action = function(dir)
              require("config.workspace").open(dir, { drop_buf = vim.api.nvim_get_current_buf() })
            end,
          },
        },
        { icon = " ", title = "Recent Files", section = "recent_files", indent = 2, padding = 1 },
        { section = "startup" },
      },
      preset = {
        keys = {
          {
            icon = " ",
            key = "p",
            desc = "Recent project",
            action = into_this_tab(function(opts)
              require("config.workspace").pick_new(opts)
            end),
          },
          {
            icon = " ",
            key = "o",
            desc = "Open project",
            action = into_this_tab(function(opts)
              require("config.workspace").explore(opts)
            end),
          },
          {
            icon = " ",
            key = "f",
            desc = "Find file",
            action = function()
              Snacks.picker.files()
            end,
          },
          {
            icon = " ",
            key = "r",
            desc = "Recent file",
            action = function()
              Snacks.picker.recent()
            end,
          },
          {
            icon = " ",
            key = "g",
            desc = "Live grep",
            action = function()
              Snacks.picker.grep()
            end,
          },
          { icon = " ", key = "n", desc = "New file", action = ":ene | startinsert" },
          {
            icon = " ",
            key = "c",
            desc = "Config",
            action = function()
              require("config.workspace").open(
                vim.fn.stdpath("config"),
                { drop_buf = vim.api.nvim_get_current_buf() }
              )
            end,
          },
          { icon = "󰒲 ", key = "L", desc = "Lazy", action = ":Lazy" },
          { icon = " ", key = "q", desc = "Quit", action = ":qa" },
        },
      },
    },
  },
}
