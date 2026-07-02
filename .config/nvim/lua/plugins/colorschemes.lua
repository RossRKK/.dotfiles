-- Alternate colorschemes kept installed for switching via `:Telescope colorscheme`.
-- The active one is set in theme.lua (tokyonight). Loaded so they register in the picker.
return {
  { "scottmckendry/cyberdream.nvim", lazy = false },
  { "Mofiqul/dracula.nvim", lazy = false },
  { "nyoom-engineering/oxocarbon.nvim", lazy = false },
  { "EdenEast/nightfox.nvim", lazy = false },
  {
    "loctvl842/monokai-pro.nvim",
    lazy = false,
    config = function()
      require("monokai-pro").setup()
    end,
  },
}
