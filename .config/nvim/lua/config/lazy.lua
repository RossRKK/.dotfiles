local build = require("util.nix_build").build

if build then
  -- Every plugin comes from the nix build (nvim-package.nix): lazy.nvim only
  -- decides when each loads, from its store path, and never fetches or writes.
  require("lazy").setup("plugins", {
    change_detection = { enabled = false },
    dev = {
      path = require("config.plugin_dirs").for_build(build, vim.env.NVIM_DEV_PLUGINS),
      patterns = { "" },
      fallback = false,
    },
    install = { missing = false },
    checker = { enabled = false },
    rocks = { enabled = false },
    -- Not the config's lazy-lock.json, which is read-only in the store.
    lockfile = vim.fn.stdpath("state") .. "/lazy-lock.json",
    -- lazy's reset would drop the nix pack dir and put ~/.config/nvim (the live
    -- checkout, not this build's config) back on the runtimepath.
    performance = { reset_packpath = false, rtp = { reset = false } },
  })
  return
end

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
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
  -- Local-first plugins developed alongside this config (fishmonger.nvim,
  -- triage.nvim, nitpick.nvim). `dev = true` on their specs loads from ~/dev
  -- when a checkout is present there; `fallback = true` clones the published
  -- GitHub repo instead when it isn't -- so the config works on a fresh machine
  -- without the local checkouts, and uses them when you have them.
  dev = { path = vim.fn.expand("~/dev"), fallback = true },
  -- image.nvim ships a rockspec depending on the `magick` luarock, which lazy's
  -- rocks support would keep trying (and failing) to build via hererocks. We use
  -- image.nvim's magick_cli processor, so no luarock is needed -- disable rocks.
  rocks = { enabled = false },
})
