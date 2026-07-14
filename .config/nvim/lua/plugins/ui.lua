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
        -- Show the path relative to cwd, not just the name, to tell apart
        -- same-named files in different folders.
        lualine_c = {
          { "filename", path = 1 },
          -- Review-mode status: the base being reviewed against and which comment
          -- categories are shown. Empty (hidden) while review mode is off.
          {
            function()
              return require("review").statusline()
            end,
            cond = function()
              return package.loaded["review"] ~= nil and require("review").enabled
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
