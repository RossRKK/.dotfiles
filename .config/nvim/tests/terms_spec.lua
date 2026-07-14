-- Slot bookkeeping in config/terms.lua: which terminal occupies the side panel,
-- which stay alive but hidden, and how renumbering moves them around.
--
-- snacks.terminal is faked: the real terminal spawns a pty and owns a window,
-- neither of which exists headlessly. Everything under test is our own slot
-- table, and the only Snacks.win surface terms.lua touches is
-- .open()/win_valid/show/hide/.buf (plus buffer deletion on kill).

local assert = require("luassert")

-- Fake Snacks.win terminals. Each gets a real (scratch) buffer so slot_of_buf and
-- the kill() path -- which deletes the buffer with nvim_buf_delete -- behave like
-- the real thing. slot_of_buf(nvim_get_current_buf()) still won't match a fake
-- (the test never focuses one), so every command resolves through open_managed(),
-- the same path taken when <C-b> is pressed from the editor.
local FakeWin = {}
FakeWin.__index = FakeWin

function FakeWin.new()
  local buf = vim.api.nvim_create_buf(false, true)
  return setmetatable({ buf = buf, win = -1, shown = true }, FakeWin)
end

-- Real Snacks.win:win_valid() checks only the window handle, but a killed
-- terminal has its buffer wiped (which closes the window), so folding buffer
-- validity in here lets the kill test observe the shutdown without a live pty.
function FakeWin:win_valid()
  return self.shown and self.buf ~= nil and vim.api.nvim_buf_is_valid(self.buf)
end

function FakeWin:show()
  self.shown = true
  return self
end

function FakeWin:hide()
  self.shown = false
  return self
end

--- A fresh config.terms with the snacks.terminal fake installed and no slot
--- state. .open() returns an already-shown terminal, mirroring the real module
--- (it opens the split and starts the job before returning).
local function fresh_terms()
  package.loaded["snacks.terminal"] = {
    open = function()
      return FakeWin.new()
    end,
  }
  package.loaded["config.terms"] = nil
  return require("config.terms")
end

--- The occupied slots, sorted.
local function slots_of(terms)
  local out = {}
  for slot in pairs(terms.slots) do
    out[#out + 1] = slot
  end
  table.sort(out)
  return out
end

--- The slot whose terminal is currently open, or nil if the panel is hidden.
local function open_slot(terms)
  for slot, term in pairs(terms.slots) do
    if term:win_valid() then
      return slot
    end
  end
end

describe("terms.show", function()
  local terms

  before_each(function()
    terms = fresh_terms()
  end)

  it("creates a terminal in an empty slot and makes it current", function()
    terms.show(3)
    assert.same({ 3 }, slots_of(terms))
    assert.equals(3, terms.current)
    assert.equals(3, open_slot(terms))
  end)

  it("reuses the existing terminal when the slot is shown again", function()
    terms.show(1)
    local first = terms.slots[1]
    terms.show(1)
    assert.equals(first, terms.slots[1])
  end)

  -- tmux-window semantics: switching away hides the old terminal rather than
  -- killing it, so its tab (and scrollback) survives the switch.
  it("hides the previous terminal but keeps it as a tab", function()
    terms.show(1)
    local first = terms.slots[1]
    terms.show(2)

    assert.same({ 1, 2 }, slots_of(terms))
    assert.is_false(first:win_valid())
    assert.equals(2, open_slot(terms))
    assert.equals(2, terms.current)
  end)

  it("clamps a slot below the first one", function()
    terms.show(0)
    assert.same({ 1 }, slots_of(terms))
    assert.equals(1, terms.current)
  end)

  it("clamps a slot above the last one", function()
    terms.show(99)
    assert.same({ 9 }, slots_of(terms))
    assert.equals(9, terms.current)
  end)
end)

describe("terms.new", function()
  local terms

  before_each(function()
    terms = fresh_terms()
  end)

  it("opens the lowest free slot", function()
    terms.new()
    assert.same({ 1 }, slots_of(terms))
    terms.new()
    assert.same({ 1, 2 }, slots_of(terms))
    assert.equals(2, terms.current)
  end)

  it("fills a hole left by a closed terminal", function()
    terms.show(1)
    terms.show(2)
    terms.slots[1] = nil -- as TermClose frees it

    terms.new()
    assert.same({ 1, 2 }, slots_of(terms))
    assert.equals(1, terms.current)
  end)

  it("warns instead of creating a tenth terminal", function()
    for i = 1, 9 do
      terms.show(i)
    end
    assert.equals(9, terms.current)

    local notified
    local notify = vim.notify
    -- Keep vim.notify's real arity: a narrower stub retrains lua_ls's inferred
    -- signature for the whole config.
    vim.notify = function(msg, level, opts) ---@diagnostic disable-line: unused-local
      notified = msg
    end
    local ok, err = pcall(terms.new)
    vim.notify = notify

    assert.is_true(ok, err)
    assert.is_truthy(notified and notified:match("slots in use"))
    assert.equals(9, #slots_of(terms))
    assert.equals(9, terms.current)
  end)
end)

describe("terms.move", function()
  local terms

  before_each(function()
    terms = fresh_terms()
  end)

  it("renumbers into an empty slot, freeing the source", function()
    terms.show(1)
    local term = terms.slots[1]

    terms.move(4)
    assert.same({ 4 }, slots_of(terms))
    assert.equals(term, terms.slots[4])
    assert.equals(4, terms.current)
    -- The window/buffer are untouched: only the slot label changed.
    assert.is_true(term:win_valid())
  end)

  -- A destination that is already taken must not clobber its terminal.
  it("swaps when the destination is occupied", function()
    terms.show(2)
    local hidden = terms.slots[2]
    terms.show(1)
    local shown = terms.slots[1]

    terms.move(2)
    assert.same({ 1, 2 }, slots_of(terms))
    assert.equals(shown, terms.slots[2])
    assert.equals(hidden, terms.slots[1])
    assert.equals(2, terms.current)
  end)

  it("does nothing when the destination is the current slot", function()
    terms.show(1)
    local term = terms.slots[1]

    terms.move(1)
    assert.same({ 1 }, slots_of(terms))
    assert.equals(term, terms.slots[1])
    assert.equals(1, terms.current)
  end)

  it("does nothing when no terminal is open", function()
    terms.move(3)
    assert.same({}, slots_of(terms))
  end)

  it("clamps the destination slot", function()
    terms.show(1)
    terms.move(99)
    assert.same({ 9 }, slots_of(terms))
    assert.equals(9, terms.current)
  end)
end)

describe("terms.kill", function()
  local terms

  before_each(function()
    terms = fresh_terms()
  end)

  -- kill() shuts the terminal's shell down by wiping its buffer; freeing the slot
  -- is then TermClose's job (see terms.new "fills a hole"), so here we only assert
  -- the buffer was deleted (which in the real module fires TermClose).
  it("shuts down the open terminal", function()
    terms.show(1)
    local term = terms.slots[1]
    local buf = term.buf

    terms.kill()
    assert.is_false(vim.api.nvim_buf_is_valid(buf))
    assert.is_false(term:win_valid())
  end)

  it("does nothing when no terminal is open", function()
    terms.kill()
    assert.same({}, slots_of(terms))
  end)
end)

describe("terms.toggle", function()
  local terms

  before_each(function()
    terms = fresh_terms()
  end)

  it("hides the open terminal without dropping its tab", function()
    terms.show(1)
    terms.toggle()

    assert.is_nil(open_slot(terms))
    assert.same({ 1 }, slots_of(terms))
    assert.equals(1, terms.current)
  end)

  it("re-shows the current tab rather than slot 1", function()
    terms.show(1)
    terms.show(3)
    terms.toggle()
    terms.toggle()

    assert.equals(3, open_slot(terms))
    assert.equals(3, terms.current)
  end)

  it("creates the first terminal when none exists", function()
    terms.toggle()
    assert.same({ 1 }, slots_of(terms))
    assert.equals(1, open_slot(terms))
  end)
end)
