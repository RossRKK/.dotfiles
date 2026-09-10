local M = {}

--- Absolute path to the uv .venv interpreter found by searching upward from
--- `start`, or nil. Search stops at the first .venv, so a jj workspace under
--- <repo>/.worktrees/x with its own .venv wins over the main checkout's.
---
--- Without `start`, anchors on the directory argument (`nvim <dir>`) when
--- present: pyright's config resolves this at startup, before explorer.lua cd's
--- into that dir, so getcwd() would still be the launch dir (e.g. ~) and miss
--- the repo's .venv.
---@param start? string directory to search upward from
---@return string?
function M.python(start)
  -- config.ide resolves the directory argument once at startup (see its notes
  -- on why argv must be read before the VimEnter cd).
  start = start or require("config.ide").dir() or vim.fn.getcwd()
  local venv = vim.fs.find(".venv", {
    upward = true,
    path = start,
    type = "directory",
    limit = 1,
  })[1]
  if venv then
    local py = venv .. "/bin/python"
    if vim.fn.executable(py) == 1 then
      return py
    end
  end
  return nil
end

return M
