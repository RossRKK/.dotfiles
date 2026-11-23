-- Where lazy.nvim loads each plugin from under the nix build (nvim-package.nix):
-- its store path, or a checkout named in NVIM_DEV_PLUGINS for developing it.
local M = {}

---@alias plugin_dirs.Dev table<string, string> plugin name -> checkout to load instead of the store

--- NVIM_DEV_PLUGINS is a comma-separated list of `name` (the checkout at
--- `<dev_root>/<name>`) or `name=dir` (any checkout, e.g. a worktree).
---@param value string|nil
---@param dev_root string
---@return plugin_dirs.Dev
function M.parse_dev(value, dev_root)
  local dev = {}
  for _, entry in ipairs(vim.split(value or "", ",", { trimempty = true })) do
    local item = vim.trim(entry)
    local name, dir = item:match("^([^=]+)=(.+)$")
    if name then
      dev[name] = dir
    elseif item ~= "" then
      dev[item] = dev_root .. "/" .. item
    end
  end
  return dev
end

--- A lazy.nvim `dev.path`. Errors rather than falling back, so a missing plugin
--- or checkout is never silently replaced by something else.
---@param nix_dirs table<string, string> plugin name -> its directory in the build
---@param link_root string where to link a checkout whose directory has another name
---@param dev plugin_dirs.Dev
---@return fun(plugin: { name: string }): string
function M.resolver(nix_dirs, link_root, dev)
  for name in pairs(dev) do
    if not nix_dirs[name] then
      error("NVIM_DEV_PLUGINS: " .. name .. " isn't a plugin in the nix build", 0)
    end
  end
  return function(plugin)
    local checkout = dev[plugin.name]
    if checkout then
      if vim.fn.isdirectory(checkout) == 0 then
        error("NVIM_DEV_PLUGINS: no checkout of " .. plugin.name .. " at " .. checkout, 0)
      end
      return M.named(plugin.name, checkout, link_root)
    end
    return nix_dirs[plugin.name]
      or error(plugin.name .. " isn't in the nix build: add it to nvim-package.nix", 0)
  end
end

--- `dir`, or a link to it named `name`: lazy tells which plugin a require()d
--- module belongs to by the name of the directory above lua/, and loads a module
--- it can't place without the plugin's opts or config.
---@param name string
---@param dir string
---@param link_root string
---@return string
function M.named(name, dir, link_root)
  if vim.fs.basename(dir) == name then
    return dir
  end
  local link = link_root .. "/" .. name
  vim.fn.mkdir(link_root, "p")
  vim.uv.fs_unlink(link)
  assert(vim.uv.fs_symlink(dir, link))
  return link
end

--- The resolver for a nix build (util.nix_build) and a NVIM_DEV_PLUGINS value.
---@param build nix_build.Build
---@param dev_value string|nil
---@return fun(plugin: { name: string }): string
function M.for_build(build, dev_value)
  return M.resolver(
    build.plugin_dirs,
    vim.fn.stdpath("cache") .. "/dev-plugins",
    M.parse_dev(dev_value, vim.fn.expand("~/dev"))
  )
end

return M
