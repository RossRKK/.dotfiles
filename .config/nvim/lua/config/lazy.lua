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
  -- Don't clone missing plugins at startup: installs are a deliberate,
  -- switch-time step (the install+restore activation hook in base.nix, which
  -- also records new specs in lazy-lock.json). A newly added spec stays
  -- uninstalled until the next `hms` -- or a manual :Lazy install, e.g. on a
  -- machine not managed by home-manager. (:Lazy restore skips uninstalled
  -- plugins, so it alone won't pick up new specs.)
  install = { missing = false },
  -- image.nvim ships a rockspec depending on the `magick` luarock, which lazy's
  -- rocks support would keep trying (and failing) to build via hererocks. We use
  -- image.nvim's magick_cli processor, so no luarock is needed -- disable rocks.
  rocks = { enabled = false },
})
