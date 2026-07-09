local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  -- stylua: ignore
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins", {
  change_detection = { notify = false },
  -- image.nvim ships a rockspec depending on the `magick` luarock, which lazy's
  -- rocks support would keep trying (and failing) to build via hererocks. We use
  -- image.nvim's magick_cli processor, so no luarock is needed -- disable rocks.
  rocks = { enabled = false },
})
