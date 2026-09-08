return {
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        theme = "auto",
        globalstatus = true,
      },
      sections = {
        -- jj-aware VCS fragment: `main+2 umzvrvxs` in a jj repo (stock `branch`
        -- shows the detached HEAD's hash there), the git branch elsewhere; and
        -- a `diff` fed by whichever of gitsigns/jjsigns owns the buffer.
        lualine_b = {
          {
            function()
              return require("util.vcsline").branch()
            end,
            icon = "",
          },
          {
            "diff",
            source = function()
              return require("util.vcsline").diff_source()
            end,
          },
          "diagnostics",
        },
        -- Show the path relative to cwd, not just the name, to tell apart
        -- same-named files in different folders.
        lualine_c = {
          { "filename", path = 1 },
          -- Review-mode status: triage contributes the base being reviewed
          -- against; nitpick contributes a comment bubble + shown categories.
          -- Empty (hidden) while review mode is off.
          {
            function()
              local triage = require("triage").statusline()
              local nitpick = package.loaded["nitpick"] and require("nitpick").statusline() or ""
              return vim.trim(triage .. (nitpick ~= "" and ("  " .. nitpick) or ""))
            end,
            cond = function()
              -- is_enabled() is per repo (cwd's), so the fragment only shows in
              -- tabs whose project is actually under review.
              return package.loaded["triage"] ~= nil and require("triage").is_enabled()
            end,
          },
        },
      },
    },
  },
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    opts = {},
  },
}
