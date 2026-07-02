-- Per-language wrap guide (vertical ruler), mirroring the repo's `wrap_guides`
-- in Zed's settings.json. `colorcolumn` is Neovim's equivalent.
local colorcolumn_by_filetype = {
  python = "88",
  rust = "100",
  typescript = "80",
  typescriptreact = "80", -- Zed "TSX"
  javascript = "80",
  javascriptreact = "80",
  svelte = "80",
}

vim.api.nvim_create_autocmd("FileType", {
  pattern = vim.tbl_keys(colorcolumn_by_filetype),
  callback = function(args)
    vim.opt_local.colorcolumn = colorcolumn_by_filetype[vim.bo[args.buf].filetype]
  end,
})

-- autoread only reloads when nudged; check on focus/idle/buffer-switch.
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI", "TermClose", "TermLeave" }, {
  callback = function()
    if vim.fn.mode() ~= "c" and vim.fn.getcmdwintype() == "" then
      vim.cmd("checktime")
    end
  end,
})

vim.api.nvim_create_autocmd("FileChangedShellPost", {
  callback = function()
    vim.notify("File changed on disk — buffer reloaded", vim.log.levels.WARN)
  end,
})
