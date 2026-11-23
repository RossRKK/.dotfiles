-- Markdown on a snacks dashboard: rows the dashboard leaves blank, covered by a
-- float that shows a markdown buffer, so render-markdown (plugins/render-markdown.lua)
-- renders it as it would any markdown file.
--
-- A dashboard is plain text with highlight extmarks, which render-markdown has
-- no parser to attach to; snacks' own terminal section overlays rows the same way.

local M = {}

local attach -- defined below M.close

-- Per dashboard buffer: the markdown buffer it shows, the float showing it while there is one,
-- and the dashboard that last drew it, to redraw when the buffer is shown again.
---@type table<integer, { buf: integer, win: integer?, dash: table? }>
local overlays = {}
M._overlays = overlays -- exposed for tests only

-- Above the dashboard but under every other float, as snacks' terminal sections.
local ZINDEX = 11

--- A dashboard item reserving `height` rows of `owner`, drawn over with `lines` as markdown.
---@param owner integer the dashboard's buffer
---@param lines string[] markdown
---@param width integer
---@param height integer
---@return table item
function M.item(owner, lines, width, height)
  return {
    text = ("\n"):rep(height - 1),
    markdown = lines,
    render = function(dash, pos)
      -- Scheduled: snacks calls this before it writes the rows, and a float placed
      -- past the end of a buffer is pinned to its last line.
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(dash.win) and vim.api.nvim_win_get_buf(dash.win) == owner then
          M.show(
            owner,
            dash,
            lines,
            { row = pos[1] - 1, col = pos[2] + 1, width = width, height = height }
          )
        end
      end)
    end,
  }
end

--- Cover `win`'s rows of `owner` from `at` with `lines` rendered as markdown,
--- moving the float `owner` already has rather than stacking another.
---@param owner integer
---@param dash { win: integer, update: fun(self) } the dashboard drawing `owner` in `dash.win`
---@param lines string[]
---@param at { row: integer, col: integer, width: integer, height: integer } 0-based buffer position
function M.show(owner, dash, lines, at)
  local overlay = overlays[owner] or attach(owner)
  overlay.dash = dash
  if not vim.deep_equal(vim.api.nvim_buf_get_lines(overlay.buf, 0, -1, false), lines) then
    vim.bo[overlay.buf].modifiable = true
    vim.api.nvim_buf_set_lines(overlay.buf, 0, -1, false, lines)
    vim.bo[overlay.buf].modifiable = false
  end
  local config = {
    relative = "win",
    win = dash.win,
    bufpos = { at.row, at.col },
    row = 0,
    col = 0,
    width = at.width,
    height = at.height,
  }
  if overlay.win and vim.api.nvim_win_is_valid(overlay.win) then
    vim.api.nvim_win_set_config(overlay.win, config)
    return
  end
  overlay.win = vim.api.nvim_open_win(
    overlay.buf,
    false,
    vim.tbl_extend(
      "force",
      config,
      { focusable = false, style = "minimal", border = "none", zindex = ZINDEX }
    )
  )
  local wo = vim.wo[overlay.win]
  wo.wrap, wo.linebreak, wo.breakindent = true, true, true
  -- No wrap marker, so prose wraps to the rows the dashboard reserved for it.
  wo.showbreak = "NONE"
  wo.winhighlight = "NormalFloat:Normal"
end

--- Close `owner`'s float, keeping its buffer for the next show().
---@param owner integer
function M.close(owner)
  local overlay = overlays[owner]
  if overlay and overlay.win then
    pcall(vim.api.nvim_win_close, overlay.win, true)
    overlay.win = nil
  end
end

--- The markdown buffer for `owner`, and the autocmds that keep its float on `owner`'s window:
--- gone while `owner` is hidden, back when it is shown, and freed with it.
---@param owner integer
---@return { buf: integer, win: integer?, dash: table? }
function attach(owner)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "markdown"
  overlays[owner] = { buf = buf }
  vim.api.nvim_create_autocmd("BufWinLeave", {
    buffer = owner,
    callback = function()
      M.close(owner)
    end,
  })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    buffer = owner,
    callback = function()
      -- Scheduled: the window shows `owner` only once the command that put it there is done.
      vim.schedule(function()
        local dash = overlays[owner] and overlays[owner].dash
        if dash and vim.fn.bufwinid(owner) ~= -1 then
          pcall(dash.update, dash)
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = owner,
    callback = function()
      M.close(owner)
      overlays[owner] = nil
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end,
  })
  return overlays[owner]
end

return M
