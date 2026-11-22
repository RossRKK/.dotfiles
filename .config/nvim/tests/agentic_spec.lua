-- plugins/agentic.lua: the chat's buffers as agentic builds them under this
-- config's opts. Runs agentic.nvim as lazy's dev path resolves it, its setup() given the spec's opts.

local assert = require("luassert")

local agentic = vim.fn.expand("~/dev/agentic.nvim")
if vim.fn.isdirectory(agentic) == 0 then
  agentic = vim.fn.stdpath("data") .. "/lazy/agentic.nvim"
end
vim.opt.runtimepath:prepend(agentic)

--- The lhs of every normal-mode mapping in `buf`.
local function normal_keys(buf)
  return vim.tbl_map(function(map)
    return map.lhs
  end, vim.api.nvim_buf_get_keymap(buf, "n"))
end

describe("agentic chat buffers", function()
  local widget

  before_each(function()
    require("agentic").setup(require("plugins.agentic")[1].opts)
    widget = require("agentic.ui.chat_widget"):new(function()
      return true
    end)
  end)

  after_each(function()
    widget:destroy()
  end)

  -- Hosted in a fishmonger tab, agentic's close tore the prompt away from the chat.
  it("leave q unbound in every panel", function()
    for name, buf in pairs(widget.buf_nrs) do
      assert.is_false(vim.tbl_contains(normal_keys(buf), "q"), name .. " maps q")
    end
  end)

  it("keep agentic's other widget keys", function()
    assert.is_true(vim.tbl_contains(normal_keys(widget.buf_nrs.input), "<CR>"))
  end)

  -- A preselected item was taken by Enter, so each menu needed an Esc to keep the typed text.
  it("open the prompt's completion menus with nothing selected", function()
    local input = widget.buf_nrs.input
    require("agentic.acp.slash_commands").setup_completion(input)
    assert.are.equal("menu,menuone,noselect,popup,fuzzy", vim.bo[input].completeopt)
  end)
end)

describe("agentic chat windows", function()
  local widget, owner

  --- `win`'s showbreak as drawn: its local value, else the global one.
  local function showbreak(win)
    return vim.api.nvim_get_option_value("showbreak", { win = win })
  end

  before_each(function()
    pcall(vim.cmd, "only!")
    vim.o.showbreak = "↪ "
    owner = vim.api.nvim_create_buf(false, true)
    require("agentic").setup(require("plugins.agentic")[1].opts)
    widget = require("agentic.ui.chat_widget"):new(function()
      return true
    end)
  end)

  after_each(function()
    widget:destroy()
  end)

  it("title the prompt with a bar as wide as its window, its text at the left", function()
    widget:show({ focus_prompt = false })
    -- agentic draws its titles on the next tick.
    vim.wait(1000, function()
      return vim.wo[widget.win_nrs.input].winbar ~= ""
    end)
    local winbar = vim.wo[widget.win_nrs.input].winbar
    assert.is_truthy(winbar:find("^%%#Normal#%%#[%w]+# "), winbar)
    assert.is_truthy(winbar:find("%%=$"), winbar)
  end)

  it("draw no wrap marker in agentic's own windows", function()
    widget:show({ focus_prompt = false })
    for name, win in pairs(widget.win_nrs) do
      assert.are.equal("NONE", showbreak(win), name)
    end
  end)

  it("draw no wrap marker in a host window, and leave its other buffers the global one", function()
    local host = vim.api.nvim_open_win(owner, false, { split = "right", win = -1 })
    widget:show({ win = host, focus_prompt = false })
    assert.are.equal("NONE", showbreak(host))
    assert.are.equal("NONE", showbreak(widget.win_nrs.input))

    -- As fishmonger switches tabs: the chat told it is leaving, then another tab's buffer into the window.
    widget:hide()
    vim.api.nvim_win_set_buf(host, vim.api.nvim_create_buf(false, true))
    assert.are.equal("↪ ", showbreak(host))
    vim.api.nvim_win_set_buf(host, owner)
    assert.are.equal("↪ ", showbreak(host))
  end)
end)
