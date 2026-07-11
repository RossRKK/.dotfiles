return {
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    dependencies = { "hrsh7th/nvim-cmp" },
    opts = {
      -- Don't add a closing pair when the next char is a letter/quote, and use
      -- treesitter to skip pairing quotes in spots where it'd be wrong.
      check_ts = true,
      fast_wrap = {}, -- <M-e> to wrap the next word/quote in a pair
    },
    config = function(_, opts)
      local npairs = require("nvim-autopairs")
      npairs.setup(opts)

      -- When cmp confirms a function/method, insert the () for you.
      local ok, cmp = pcall(require, "cmp")
      if ok then
        cmp.event:on(
          "confirm_done",
          require("nvim-autopairs.completion.cmp").on_confirm_done()
        )
      end
    end,
  },
}
