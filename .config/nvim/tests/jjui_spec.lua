-- The one decision in util/jjui.lua that can go wrong silently: which
-- directory jjui runs in. A nil cwd reaches jobstart and inherits nvim's
-- GLOBAL cwd, so in a workspace tab (:tcd) jjui would show the main
-- workspace's `@`. Snacks is stubbed; only the cwd it is handed is checked.

local assert = require("luassert")

describe("jjui.float", function()
  local got, saved_snacks, saved_cwd

  before_each(function()
    got = nil
    saved_snacks = _G.Snacks
    saved_cwd = vim.fn.getcwd()
    _G.Snacks = {
      terminal = {
        toggle = function(_, opts)
          got = opts.cwd
          return { win_valid = function() return false end, hide = function() end }
        end,
      },
    }
  end)

  after_each(function()
    _G.Snacks = saved_snacks
    vim.cmd.tabonly()
    vim.cmd.cd(vim.fn.fnameescape(saved_cwd))
  end)

  it("runs jjui in the tab-local cwd, not the global one", function()
    local main = vim.fn.getcwd(-1, 1)
    local other = vim.fn.tempname()
    vim.fn.mkdir(other, "p")
    vim.cmd.tabnew()
    vim.cmd.tcd(vim.fn.fnameescape(other))
    require("util.jjui").float()
    assert.equals(vim.fn.getcwd(0), got)
    assert.equals(other, got)
    assert.is_not.equals(main, got)
  end)

  it("keeps an explicit cwd (the project picker path)", function()
    require("util.jjui").float("/some/repo")
    assert.equals("/some/repo", got)
  end)
end)
