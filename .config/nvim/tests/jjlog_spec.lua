-- ANSI parsing and width-cutting in util/jjlog.lua: the two decisions that
-- would otherwise show up as a mis-coloured or crooked graph on the greeter.
-- jj itself is not run here.

local assert = require("luassert")
local jjlog = require("util.jjlog")

local ESC = "\27["

describe("jjlog.parse", function()
  it("gives plain text one uncoloured chunk", function()
    local chunks = jjlog.parse("fix starship support")
    assert.equals(1, #chunks)
    assert.equals("fix starship support", chunks[1][1])
    assert.is_nil(chunks[1].hl)
  end)

  it("splits on 256-colour codes and keeps bold", function()
    -- jj's working-copy marker: bold green @, then a reset.
    local chunks = jjlog.parse(ESC .. "1m" .. ESC .. "38;5;2m@" .. ESC .. "0m  rest")
    assert.equals("@", chunks[1][1])
    assert.equals(2, chunks[1].fg)
    assert.is_true(chunks[1].bold)
    assert.equals("GreeterAnsi2b", chunks[1].hl)
    assert.equals("  rest", chunks[2][1])
    assert.is_nil(chunks[2].fg)
  end)

  it("treats 39 as back to the default colour", function()
    local chunks = jjlog.parse(ESC .. "38;5;8mgrey" .. ESC .. "39m plain")
    assert.equals(8, chunks[1].fg)
    assert.is_nil(chunks[2].fg)
    assert.equals("GreeterAnsi8", chunks[1].hl)
  end)

  it("merges neighbouring chunks of one colour", function()
    local chunks = jjlog.parse(ESC .. "38;5;5mm" .. ESC .. "38;5;5mlzv")
    assert.equals(1, #chunks)
    assert.equals("mlzv", chunks[1][1])
  end)

  it("drops the escape bytes from the text", function()
    local text = ""
    for _, c in ipairs(jjlog.parse(ESC .. "1m" .. ESC .. "38;5;14m\226\151\134" .. ESC .. "0m  x")) do
      text = text .. c[1]
    end
    assert.equals("\226\151\134  x", text)
  end)
end)

describe("jjlog.truncate", function()
  local function text(chunks)
    local s = ""
    for _, c in ipairs(chunks) do
      s = s .. c[1]
    end
    return s
  end

  it("leaves a line that fits alone", function()
    local chunks = { { "short" } }
    assert.same(chunks, jjlog.truncate(chunks, 10))
  end)

  it("cuts to the width with an ellipsis in the last column", function()
    local out = jjlog.truncate({ { "abc" }, { "defghij" } }, 6)
    assert.equals("abcde\226\128\166", text(out))
    assert.equals(6, vim.fn.strdisplaywidth(text(out)))
  end)

  -- The graph column is box drawing: every glyph is multibyte, and a byte-wise
  -- cut would leave half a character on the line.
  it("cuts between whole multibyte characters", function()
    local rails = "\226\148\130 \226\151\139  " -- "│ ○  "
    local out = jjlog.truncate({ { rails }, { "a very long description" } }, 8)
    assert.equals(8, vim.fn.strdisplaywidth(text(out)))
    assert.equals(rails .. "a \226\128\166", text(out))
  end)

  it("keeps the colour of the chunk it cuts", function()
    local out = jjlog.truncate({ { "abcdef", hl = "X", fg = 1, bold = false } }, 4)
    assert.equals("abc", out[1][1])
    assert.equals("X", out[1].hl)
  end)
end)

describe("jjlog.items", function()
  it("makes one left-aligned item per line, skipping blank ones", function()
    local items = jjlog.items("@  one\n\226\148\130  two\n", 60)
    assert.equals(2, #items)
    assert.is_nil(items[1].align)
    assert.equals("@  one", items[1].text[1][1])
  end)

  it("cuts every line to the pane width", function()
    local items = jjlog.items(("x"):rep(80) .. "\n" .. ("y"):rep(10), 60)
    local w = 0
    for _, c in ipairs(items[1].text) do
      w = w + vim.fn.strdisplaywidth(c[1])
    end
    assert.equals(60, w)
    assert.equals(("y"):rep(10), items[2].text[1][1])
  end)
end)
