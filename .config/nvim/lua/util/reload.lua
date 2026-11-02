-- Hot reload for this config's own modules (:ConfigReload, <leader>C): re-run
-- every module under lua/ whose file changed since it was loaded, in place, so
-- open workspaces, terminals and agents survive. lua/plugins/ is lazy.nvim's
-- (its specs only take effect on restart) and is left alone.
--
-- Modules load through M.setup's searcher, which records the keymaps and
-- autocmds each module body creates. Reloading a module deletes those, runs the
-- new body, and copies its functions into the table every caller already holds.
-- The new functions' non-function upvalues are joined to the old ones of the
-- same name, so module state (caches, handles, the module table itself) carries
-- over -- which also means an edited module-level constant needs a restart.

local M = {}

---@class reload.Module
---@field path string
---@field mtime { sec: integer, nsec: integer }
---@field maps { mode: string, lhs: string, buffer?: integer }[]
---@field autocmds integer[]

---@type table<string, reload.Module>
local modules = {}

--- The module whose body is running, so its side effects are recorded on it.
---@type reload.Module?
local running

--- The file `mod` lives in under `root`, if it is one this reloader manages.
---@param root string
---@param mod string
---@return string?
local function path_of(root, mod)
  if mod:match("^plugins%.") or mod == "util.reload" then
    return nil
  end
  local base = root .. "/" .. (mod:gsub("%.", "/"))
  for _, path in ipairs({ base .. ".lua", base .. "/init.lua" }) do
    if vim.uv.fs_stat(path) then
      return path
    end
  end
end

--- Run `chunk` as `mod`'s body, recording what it maps and hooks.
---@param mod string
---@param path string
---@param chunk function
---@return any result what the body returned
local function run(mod, path, chunk)
  local module = { path = path, mtime = vim.uv.fs_stat(path).mtime, maps = {}, autocmds = {} }
  modules[mod] = module
  local outer = running
  running = module
  local ok, result = pcall(chunk, mod, path)
  running = outer
  if not ok then
    error(result, 0)
  end
  return result
end

---@param module reload.Module
local function undo(module)
  -- pcall: a buffer-local map's buffer may be gone, or the map already removed.
  for _, map in ipairs(module.maps) do
    pcall(vim.keymap.del, map.mode, map.lhs, { buffer = map.buffer })
  end
  for _, id in ipairs(module.autocmds) do
    pcall(vim.api.nvim_del_autocmd, id)
  end
end

--- Every function defined in `path` reachable from `roots` through upvalues.
---@param roots table
---@param path string
---@return function[]
local function functions_in(roots, path)
  local found, seen = {}, {}
  local function visit(fn)
    if seen[fn] or debug.getinfo(fn, "S").source ~= "@" .. path then
      return
    end
    seen[fn] = true
    found[#found + 1] = fn
    for i = 1, debug.getinfo(fn, "u").nups do
      local _, value = debug.getupvalue(fn, i)
      if type(value) == "function" then
        visit(value)
      end
    end
  end
  for _, value in pairs(roots) do
    if type(value) == "function" then
      visit(value)
    end
  end
  return found
end

--- Join `fresh`'s functions' non-function upvalues to `live`'s of the same name.
---@param live table
---@param fresh table
---@param path string
local function carry_state(live, fresh, path)
  local cells = {}
  for _, fn in ipairs(functions_in(live, path)) do
    for i = 1, debug.getinfo(fn, "u").nups do
      local name, value = debug.getupvalue(fn, i)
      if type(value) ~= "function" and not cells[name] then
        cells[name] = { fn = fn, index = i }
      end
    end
  end
  for _, fn in ipairs(functions_in(fresh, path)) do
    for i = 1, debug.getinfo(fn, "u").nups do
      local name, value = debug.getupvalue(fn, i)
      local cell = cells[name]
      if cell and type(value) ~= "function" then
        debug.upvaluejoin(fn, i, cell.fn, cell.index)
      end
    end
  end
end

---@param mod string
---@param module reload.Module
local function reload_one(mod, module)
  local chunk, err = loadfile(module.path)
  if not chunk then
    error(err, 0)
  end
  undo(module)
  local fresh = run(mod, module.path, chunk)
  local live = package.loaded[mod]
  if type(live) ~= "table" or type(fresh) ~= "table" then
    package.loaded[mod] = fresh == nil and true or fresh
    return
  end
  carry_state(live, fresh, module.path)
  for key, value in pairs(fresh) do
    if type(value) == "function" or live[key] == nil then
      live[key] = value
    end
  end
end

--- Re-run every managed module whose file changed since it was loaded.
---@return { reloaded: string[], failed: table<string, string> }
function M.reload()
  local result = { reloaded = {}, failed = {} }
  for mod, module in pairs(modules) do
    local stat = vim.uv.fs_stat(module.path)
    if stat and (stat.mtime.sec ~= module.mtime.sec or stat.mtime.nsec ~= module.mtime.nsec) then
      local ok, err = pcall(reload_one, mod, module)
      if ok then
        table.insert(result.reloaded, mod)
      else
        result.failed[mod] = err
      end
    end
  end
  table.sort(result.reloaded)
  return result
end

local function notify(result)
  for mod, err in pairs(result.failed) do
    vim.notify(mod .. ": " .. err, vim.log.levels.ERROR)
  end
  if #result.reloaded > 0 then
    vim.notify("reloaded " .. table.concat(result.reloaded, ", "))
  elseif vim.tbl_isempty(result.failed) then
    vim.notify("config: nothing changed")
  end
end

--- Load the modules under `root` through the reloader. Call before requiring any.
---@param root string the lua/ directory of the config
function M.setup(root)
  local set, create = vim.keymap.set, vim.api.nvim_create_autocmd
  vim.keymap.set = function(mode, lhs, rhs, opts)
    if running then
      local buffer = opts and opts.buffer
      if buffer == true or buffer == 0 then
        buffer = vim.api.nvim_get_current_buf()
      end
      for _, m in ipairs(type(mode) == "table" and mode or { mode }) do
        table.insert(running.maps, { mode = m, lhs = lhs, buffer = buffer })
      end
    end
    return set(mode, lhs, rhs, opts)
  end
  vim.api.nvim_create_autocmd = function(event, opts)
    local id = create(event, opts)
    if running then
      table.insert(running.autocmds, id)
    end
    return id
  end
  -- First, ahead of vim.loader's searcher, which would otherwise find these too.
  table.insert(package.loaders, 1, function(mod)
    local path = path_of(root, mod)
    if not path then
      return nil
    end
    local chunk, err = loadfile(path)
    if not chunk then
      return "\n\t" .. err
    end
    return function()
      return run(mod, path, chunk)
    end
  end)
  vim.api.nvim_create_user_command("ConfigReload", function()
    notify(M.reload())
  end, { desc = "Re-run config modules changed since they were loaded" })
end

return M
