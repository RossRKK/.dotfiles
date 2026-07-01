return {
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        theme = "tokyonight",
        globalstatus = true,
      },
      sections = {
        -- Show the path relative to cwd, not just the name, to tell apart
        -- same-named files in different folders.
        lualine_c = { { "filename", path = 1 } },
      },
    },
  },
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    opts = {},
  },
}
