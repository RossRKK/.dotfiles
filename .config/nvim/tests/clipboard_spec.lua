local assert = require("luassert")
local clipboard = require("util.clipboard")

-- A Vim register cannot hold a NUL: the register representation rewrites each
-- one to NL. Anything arriving from getreg has already been through that, so
-- specs must assert on the transformed bytes -- testing a pristine file header
-- would pass checks that the real thing defeats.
local function as_register(s)
  return (s:gsub("%z", "\n"))
end

describe("clipboard.is_text", function()
  it("accepts ordinary text", function()
    assert.is_true(clipboard.is_text("hello world"))
    assert.is_true(clipboard.is_text("multi\nline\ttext\r\n"))
    assert.is_true(clipboard.is_text("émoji ✨ utf-8"))
  end)

  it("accepts copied terminal output carrying ANSI escapes", function()
    assert.is_true(clipboard.is_text("\27[31mred\27[0m"))
  end)

  it("rejects nothing to paste", function()
    assert.is_false(clipboard.is_text(""))
    assert.is_false(clipboard.is_text(nil))
  end)

  -- The bug this guards: bare `wl-paste` dumps raw image bytes when the source
  -- offers no text/plain, so getreg succeeds and the image would be shoved into
  -- the pty as if it were text.
  it("rejects images as a register delivers them", function()
    assert.is_false(clipboard.is_text(as_register("\137PNG\r\n\26\n\0\0\0\13IHDR")))
    assert.is_false(clipboard.is_text(as_register("\255\216\255\224\0\16JFIF")))
    assert.is_false(clipboard.is_text(as_register("GIF89a\1\0")))
    assert.is_false(clipboard.is_text(as_register("BM\54\0\0\0")))
    assert.is_false(clipboard.is_text(as_register("RIFF\0\0\0\0WEBP")))
  end)

  -- Regression: a NUL scan passes this, because there is no NUL left to find.
  it("rejects a PNG header with every NUL already rewritten to NL", function()
    local png = "\137PNG\r\n\26\n\n\n\n\rIHDR"
    assert.is_nil(png:find("%z"))
    assert.is_false(clipboard.is_text(png))
  end)

  it("rejects binary with no known magic", function()
    assert.is_false(clipboard.is_text(as_register("\1\2\3\0\4")))
  end)

  it("only sniffs the head, so a long text paste stays text", function()
    assert.is_true(clipboard.is_text(string.rep("a", 100000)))
  end)
end)
