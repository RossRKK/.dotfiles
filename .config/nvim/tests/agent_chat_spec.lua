-- config.agent_chat: toggling the agentic chat swaps it with fishmonger's side
-- terminal per tabpage. Both plugins are faked: agentic as a real split showing
-- an AgenticChat buffer, fishmonger as a per-tabpage open flag.

local assert = require("luassert")

local agent_chat
local panel -- tabpage -> whether the fake side terminal is showing
local toggles -- fishmonger.toggle() calls

--- A window in `tab` showing an AgenticChat buffer, floating or not.
local function chat_window(tab, float)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    local is_float = vim.api.nvim_win_get_config(win).relative ~= ""
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "AgenticChat" and is_float == float then
      return win
    end
  end
end

local function chat_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "AgenticChat"
  return buf
end

describe("agent_chat.toggle", function()
  before_each(function()
    pcall(vim.cmd, "tabonly!")
    pcall(vim.cmd, "only!")
    panel, toggles = {}, 0
    package.loaded["fishmonger"] = {
      panel_open = function(tab)
        return panel[tab or vim.api.nvim_get_current_tabpage()] == true
      end,
      toggle = function()
        local tab = vim.api.nvim_get_current_tabpage()
        panel[tab] = not panel[tab]
        toggles = toggles + 1
      end,
    }
    package.loaded["agentic"] = {
      open = function()
        vim.cmd("botright vsplit")
        vim.api.nvim_win_set_buf(0, chat_buf())
      end,
      close = function()
        local win = chat_window(vim.api.nvim_get_current_tabpage(), false)
        if win then
          vim.api.nvim_win_close(win, true)
        end
      end,
    }
    package.loaded["config.agent_chat"] = nil
    agent_chat = require("config.agent_chat")
  end)

  after_each(function()
    package.loaded["fishmonger"] = nil
    package.loaded["agentic"] = nil
  end)

  it("hides a showing side terminal to open the chat, and brings it back on close", function()
    local tab = vim.api.nvim_get_current_tabpage()
    panel[tab] = true

    agent_chat.toggle()
    assert.is_not_nil(chat_window(tab, false))
    assert.is_false(panel[tab])

    agent_chat.toggle()
    assert.is_nil(chat_window(tab, false))
    assert.is_true(panel[tab])
  end)

  it("leaves a hidden side terminal hidden on both open and close", function()
    local tab = vim.api.nvim_get_current_tabpage()

    agent_chat.toggle()
    agent_chat.toggle()

    assert.equals(0, toggles)
    assert.is_nil(chat_window(tab, false))
  end)

  it("restores on the next close after the chat was closed some other way", function()
    local tab = vim.api.nvim_get_current_tabpage()
    panel[tab] = true
    agent_chat.toggle()
    vim.api.nvim_win_close(chat_window(tab, false), true) -- :q on the chat

    agent_chat.toggle() -- reopens the chat, the terminal stays hidden
    assert.is_not_nil(chat_window(tab, false))
    assert.is_false(panel[tab])

    agent_chat.toggle()
    assert.is_true(panel[tab])
  end)

  it("doesn't toggle a terminal the user already reopened", function()
    local tab = vim.api.nvim_get_current_tabpage()
    panel[tab] = true
    agent_chat.toggle()
    panel[tab] = true -- <C-t> while the chat is open

    agent_chat.toggle()
    assert.equals(1, toggles)
    assert.is_true(panel[tab])
  end)

  it("keeps what it hid per tabpage", function()
    local first = vim.api.nvim_get_current_tabpage()
    panel[first] = true
    agent_chat.toggle()
    vim.cmd("tabnew")
    local second = vim.api.nvim_get_current_tabpage()

    agent_chat.toggle()
    agent_chat.toggle()
    assert.is_nil(panel[second])

    vim.api.nvim_set_current_tabpage(first)
    agent_chat.toggle()
    assert.is_true(panel[first])
  end)

  it("opens the chat when only agentic's hidden float of it exists", function()
    local tab = vim.api.nvim_get_current_tabpage()
    vim.api.nvim_open_win(
      chat_buf(),
      false,
      { relative = "editor", row = 0, col = 0, width = 10, height = 5, hide = true }
    )

    agent_chat.toggle()
    assert.is_not_nil(chat_window(tab, false))
  end)
end)
