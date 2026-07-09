-- Slot bookkeeping in config/terms.lua: which terminal occupies the side panel,
-- which stay alive but hidden, and how renumbering moves them around.
--
-- toggleterm is faked: the real Terminal spawns a pty and owns a window, neither
-- of which exists headlessly. Everything under test is our own slot table, and
-- the only Terminal surface terms.lua touches is new/is_open/open/close/bufnr.

local assert = require("luassert")

-- Fake toggleterm terminals. `bufnr` starts well above any real buffer number so
-- slot_of_buf(nvim_get_current_buf()) never matches one, and every command under
-- test resolves its target through open_managed() instead -- the same path taken
-- when <C-b> is pressed from the editor rather than from a terminal.
local next_bufnr = 1000

local Terminal = {}
Terminal.__index = Terminal

function Terminal:new()
  next_bufnr = next_bufnr + 1
  return setmetatable({ bufnr = next_bufnr, opened = false }, Terminal)
end

function Terminal:is_open()
  return self.opened
end

function Terminal:open()
  self.opened = true
end

function Terminal:close()
  self.opened = false
end

--- A fresh config.terms with the toggleterm fake installed and no slot state.
local function fresh_terms()
  package.loaded["toggleterm.terminal"] = { Terminal = Terminal }
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
    if term:is_open() then
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
    assert.is_false(first:is_open())
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
    assert.is_true(term:is_open())
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
