-- plugins/agentic.lua: the chat's buffers as agentic builds them under this
-- config's opts. Runs lazy's installed agentic.nvim, its setup() given the spec's opts.

local assert = require("luassert")

vim.opt.runtimepath:prepend(vim.fn.stdpath("data") .. "/lazy/agentic.nvim")

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
end)
