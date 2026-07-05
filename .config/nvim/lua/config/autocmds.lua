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
  markdown = "80",
}

vim.api.nvim_create_autocmd("FileType", {
  pattern = vim.tbl_keys(colorcolumn_by_filetype),
  callback = function(args)
    vim.opt_local.colorcolumn = colorcolumn_by_filetype[vim.bo[args.buf].filetype]
  end,
})

-- Prose: `gq`/`gqip` reflows to this width (0 would fall back to 79).
local prose_filetypes = { "markdown", "text", "gitcommit", "rst", "tex", "typst" }

-- Markdown routes `gq`/`gw` through conform (prettierd): it reflows prose to
-- printWidth AND keeps tables aligned, unlike the built-in reflow which wraps
-- table rows and shreds them. Other prose filetypes have no conform formatter,
-- so they keep the built-in paragraph reflow (formatexpr = "").
local function set_prose_formatexpr(buf)
  if vim.bo[buf].filetype == "markdown" then
    vim.bo[buf].formatexpr = "v:lua.require'conform'.formatexpr()"
  else
    vim.bo[buf].formatexpr = ""
  end
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = prose_filetypes,
  callback = function(args)
    vim.opt_local.textwidth = 80
    set_prose_formatexpr(args.buf)
  end,
})

-- A language server (e.g. marksman on markdown) points `formatexpr` at the LSP
-- formatter on attach, clobbering the above — and marksman doesn't reflow, so
-- `gq` would appear to do nothing. Re-assert our formatexpr on LspAttach so it
-- wins over the default handler (which set it during attach).
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    if vim.tbl_contains(prose_filetypes, vim.bo[args.buf].filetype) then
      set_prose_formatexpr(args.buf)
    end
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
