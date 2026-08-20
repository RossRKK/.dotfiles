-- Workspace greeter: what the main editor window shows when it has nothing
-- real to show.
--
-- workspace.open() used to leave a plain empty buffer there, which told you
-- nothing and did nothing. Instead the window gets a snacks dashboard scoped to
-- THIS workspace: the project's recent files and the pickers, a keypress away.
-- It comes back whenever the buffer list empties out again (<leader>X, or
-- closing the last buffer), so "no buffers open" is a useful state rather than a
-- dead end.
--
-- Distinct from plugins/dashboard.lua, which is the bare-`nvim` startup greeter
-- and is about CHOOSING a project; this one assumes the project and is about
-- getting into its files. Both are snacks dashboards, so they share styling and
-- section machinery.

local M = {}

--- Is this buffer a spent one -- nothing in it, nothing to save, nobody's
--- scratch -- that the greeter may take the window from and delete? A previous
--- greeter counts too. Deliberately-blank buffers (M.new_file) are tagged out.
---
--- Requiring buflisted is what keeps a panel's buffer safe: a plugin's scratch
--- buffer is unlisted, and fishmonger's terminal buffer is empty, unnamed and
--- still buftype "" in the moment between being shown and having its shell
--- attached -- claiming that one drew a second greeter over the side terminal
--- and destroyed the buffer the shell was about to attach to.
---@param buf integer
---@return boolean
function M.is_disposable(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.b[buf].greeter_ignore then
    return false
  end
  if vim.bo[buf].filetype == "snacks_dashboard" then
    return true
  end
  return vim.bo[buf].buflisted
    and vim.api.nvim_buf_get_name(buf) == ""
    and vim.bo[buf].buftype == ""
    and vim.bo[buf].filetype == ""
    and not vim.bo[buf].modified
    and vim.api.nvim_buf_line_count(buf) == 1
    and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
end

--- Start an empty unnamed buffer to type into. A deliberately blank buffer is
--- indistinguishable from the spent one the fallback below exists to replace, so
--- it's tagged: without the tag, "New file" hands you a blank buffer and the
--- fallback immediately takes it back, which looks like the key doing nothing.
function M.new_file()
  require("config.windows").goto_main_window()
  vim.cmd.enew()
  vim.b[vim.api.nvim_get_current_buf()].greeter_ignore = true
  vim.cmd.startinsert()
end

--- Show the greeter in `win` (default: the current window). The buffer is a
--- fresh scratch one -- snacks styles it bufhidden=wipe and unlisted, so opening
--- any real file over it disposes of it without a trace.
---@param win? integer
function M.open(win)
  win = win or vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)

  -- Retire an outgoing dashboard BEFORE opening ours, never during. Every snacks
  -- dashboard shares one augroup NAME, so they share its id, and a dashboard
  -- buffer's BufWipeout deletes that augroup by id. Snacks' own open() sets the
  -- window's buffer as its first step, so letting it wipe the previous dashboard
  -- there deletes the augroup the half-built new one is still registering
  -- against -- "invalid group: N", mid-init, leaving nvim unusable. Doing the
  -- swap here means the wipe lands while no dashboard is initialising, and
  -- open() then creates the augroup fresh.
  --
  -- The spent buffer the greeter displaces goes the same way, for a different
  -- reason: Snacks.bufdelete leaves the window on a fresh empty LISTED buffer,
  -- which lingers in the buffer list as "[No Name]" on the bufferline once the
  -- greeter has taken the window over.
  local prev = vim.api.nvim_win_get_buf(win)
  if prev ~= buf and M.is_disposable(prev) then
    vim.api.nvim_win_set_buf(win, buf)
    pcall(vim.api.nvim_buf_delete, prev, { force = true })
  end

  Snacks.dashboard.open({
    win = win,
    buf = buf,
    sections = {
      {
        text = {
          {
            require("config.workspace").name(vim.api.nvim_win_get_tabpage(win)),
            hl = "SnacksDashboardHeader",
          },
        },
        align = "center",
        padding = 1,
      },
      { section = "keys", gap = 0, padding = 1 },
      {
        icon = " ",
        title = "Recent Files",
        section = "recent_files",
        cwd = true,
        limit = 8,
        indent = 2,
      },
    },
    -- The bare-nvim greeter's keys (plugins/dashboard.lua) are about picking a
    -- project; in here the project is a given, so the keys are about getting
    -- into its files.
    preset = {
      keys = {
        {
          icon = " ",
          key = "f",
          desc = "Find file",
          action = function()
            Snacks.picker.files()
          end,
        },
        {
          icon = " ",
          key = "r",
          desc = "Recent file",
          action = function()
            Snacks.picker.recent({ filter = { cwd = true } })
          end,
        },
        {
          icon = " ",
          key = "g",
          desc = "Live grep",
          action = function()
            Snacks.picker.grep()
          end,
        },
        { icon = " ", key = "n", desc = "New file", action = M.new_file },
      },
    },
  })
end

--- Close every buffer belonging to this workspace tab (the same set bufferline
--- shows: file buffers under the tab's cwd, plus unnamed ones), landing back on
--- the greeter. Modified buffers get snacks' save/discard prompt rather than
--- being lost.
function M.close_all()
  require("config.windows").goto_main_window()
  local cwd = vim.fs.normalize(require("config.workspace").cwd())
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted and vim.bo[buf].buftype == "" then
      local file = vim.api.nvim_buf_get_name(buf)
      if file == "" or vim.startswith(vim.fs.normalize(file), cwd .. "/") then
        Snacks.bufdelete(buf)
      end
    end
  end
  -- The BufEnter fallback below re-opens the greeter once the window lands on
  -- the empty replacement buffer, so nothing more to do here.
end

--- Keep the greeter as the floor of a workspace tab: whenever a window in one
--- falls back to a truly empty buffer (last buffer closed, `q` on the greeter
--- itself), show the greeter instead. Only workspace tabs -- `nvim <file>`,
--- commit messages, and the bare-nvim startup dashboard are untouched.
function M.setup()
  vim.api.nvim_create_autocmd("BufEnter", {
    group = vim.api.nvim_create_augroup("workspace_greeter", { clear = true }),
    callback = function(ev)
      local win = vim.api.nvim_get_current_win()
      local tab_is_workspace = pcall(vim.api.nvim_tabpage_get_var, 0, "workspace")
      if
        not tab_is_workspace
        or vim.bo[ev.buf].filetype == "snacks_dashboard" -- already the greeter
        or not M.is_disposable(ev.buf)
        -- Only ever the main editor window: a panel window that happens to hold
        -- a disposable-looking buffer is not the greeter's to claim.
        or win ~= require("config.windows").main_window()
        or vim.api.nvim_win_get_config(win).relative ~= ""
      then
        return
      end
      -- Deferred: swapping the window's buffer from inside BufEnter confuses
      -- whatever command put us here (bufdelete's window juggling in particular).
      --
      -- Re-tested on the way out, not just re-identified: BufEnter fires from
      -- INSIDE the command that made the buffer, so anything that command does
      -- afterwards to claim it -- M.new_file's tag, a plugin setting a filetype
      -- or attaching a job -- has only landed by now. Trusting the entry check
      -- alone made "New file" hand back the greeter instead of a blank buffer.
      vim.schedule(function()
        if
          vim.api.nvim_win_is_valid(win)
          and vim.api.nvim_win_get_buf(win) == ev.buf
          and M.is_disposable(ev.buf)
        then
          M.open(win)
        end
      end)
    end,
  })
end

return M
