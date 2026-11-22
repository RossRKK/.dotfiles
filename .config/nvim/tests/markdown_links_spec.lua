local assert = require("luassert")
local links = require("util.markdown_links")

--- The URL `url_at` finds with the cursor on the first `needle` in a markdown buffer of `lines`.
---@param lines string[]
---@param needle string
---@param filetype? string
local function url_on(lines, needle, filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = filetype or "markdown"
  for row, line in ipairs(lines) do
    local col = line:find(needle, 1, true)
    if col then
      local url = links.url_at(buf, { row, col - 1 })
      vim.api.nvim_buf_delete(buf, { force = true })
      return url
    end
  end
  error("needle not in lines: " .. needle)
end

describe("markdown_links.url_at", function()
  it("finds an inline link's URL, from its text or its destination", function()
    local lines = { "See [the docs](https://example.com/a?b=1) here." }
    assert.equals("https://example.com/a?b=1", url_on(lines, "docs"))
    assert.equals("https://example.com/a?b=1", url_on(lines, "example"))
  end)

  it("finds any scheme, an angle-bracketed destination unwrapped", function()
    assert.equals("mailto:me@example.com", url_on({ "[mail](mailto:me@example.com)" }, "mail"))
    assert.equals("http://x.test/a b", url_on({ "[x](<http://x.test/a b>)" }, "x"))
  end)

  it("finds an autolink's URL", function()
    assert.equals("https://example.com", url_on({ "Go to <https://example.com> now." }, "example"))
  end)

  it("resolves a reference link to its definition's URL", function()
    local lines =
      { "Read [the guide][Guide] and [guide].", "", "[guide]: https://example.com/guide" }
    assert.equals("https://example.com/guide", url_on(lines, "the guide"))
    assert.equals("https://example.com/guide", url_on(lines, "[guide]."))
  end)

  it("finds none for a relative file, an anchor, or a file and anchor", function()
    assert.is_nil(url_on({ "[other](other.md)" }, "other"))
    assert.is_nil(url_on({ "[sec](#second)" }, "sec"))
    assert.is_nil(url_on({ "[both](other.md#deep-part)" }, "both"))
    assert.is_nil(url_on({ "[ref][r]", "", "[r]: ./notes/r.md" }, "ref"))
  end)

  it("finds none off a link", function()
    assert.is_nil(url_on({ "plain https://example.com [x](https://example.com)" }, "plain"))
    assert.is_nil(url_on({ "[undefined][nowhere]" }, "undefined"))
  end)

  it("works in an agent chat, which registers the markdown parser", function()
    vim.treesitter.language.register("markdown", "AgenticChat")
    assert.equals("https://example.com", url_on({ "[x](https://example.com)" }, "x", "AgenticChat"))
  end)

  it("finds none in a buffer with no parser", function()
    assert.is_nil(url_on({ "[x](https://example.com)" }, "x", "no_such_language"))
  end)
end)
