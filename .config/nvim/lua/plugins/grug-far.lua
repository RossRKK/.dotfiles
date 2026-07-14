-- Project-wide find & replace: a ripgrep search in an editable results buffer
-- (regex + capture groups, live preview) that applies the replacement across
-- every match. The counterpart to the snacks picker grep, which only finds.
return {
  {
    "MagicDuck/grug-far.nvim",
    cmd = "GrugFar",
    opts = {},
    keys = {
      { "<leader>fr", "<cmd>GrugFar<cr>", desc = "Find & replace (project)" },
    },
  },
}
