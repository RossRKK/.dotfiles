-- Side-terminal shells run in systemd's background.slice, a cgroup apart from
-- nvim's, so builds and agents in them share CPU as one group instead of
-- outnumbering the editor thread for thread.
local M = {}

--- The command to start `shell` with: inside background.slice when a systemd
--- user manager can take it, else the shell as is (macOS, no systemd).
---@param shell string
---@param user_manager boolean
---@return string|string[]
function M.command(shell, user_manager)
  if not user_manager then
    return shell
  end
  -- --scope execs the shell in place, so the job pid is still the shell's.
  return { "systemd-run", "--user", "--scope", "--slice=background.slice", "--quiet", "--collect", shell }
end

--- Whether a systemd user manager is running for this session.
---@return boolean
function M.user_manager()
  local runtime = vim.env.XDG_RUNTIME_DIR
  return runtime ~= nil
    and vim.fn.executable("systemd-run") == 1
    and vim.uv.fs_stat(runtime .. "/systemd/private") ~= nil
end

return M
