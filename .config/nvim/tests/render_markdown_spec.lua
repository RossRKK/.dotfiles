-- A table rendered in an agent chat by the real render-markdown under this config's tokyonight.

local assert = require("luassert")

require("tests.helpers.plugins").add("tokyonight.nvim", "render-markdown.nvim")

-- As config/options.lua sets them, before the render-markdown spec reads them for its raw view.
vim.o.wrap = true
vim.o.linebreak = true
vim.o.breakindent = true
vim.o.showbreak = "↪ "
vim.o.breakindentopt = "sbr"

describe("a table in an agent chat", function()
  local buf, palette

  --- The resolved colour of `group` as { fg = "#rrggbb", bold = bool }.
  local function colour(group)
    local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
    return { fg = hl.fg and ("#%06x"):format(hl.fg), bold = hl.bold or false }
  end

  --- Every highlight group render-markdown draws the table's borders in.
  local function border_groups()
    local groups = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
      for _, chunk in ipairs(mark[4].virt_text or {}) do
        if chunk[1]:find("[│─┌┬┐├┼┤└┴┘]") then
          groups[chunk[2]] = true
        end
      end
    end
    local names = vim.tbl_keys(groups)
    table.sort(names)
    return names
  end

  --- The treesitter groups covering (0-based) `row`, `col`.
  local function captures_at(row, col)
    return vim.tbl_map(function(c)
      return "@" .. c.capture .. "." .. c.lang
    end, vim.treesitter.get_captures_at_pos(buf, row, col))
  end

  before_each(function()
    vim.cmd("runtime! plugin/render-markdown.lua")
    require("tokyonight").setup(require("plugins.theme")[1].opts)
    vim.cmd.colorscheme("tokyonight")
    palette = require("tokyonight.colors").setup()
    require("render-markdown").setup(require("plugins.render-markdown")[1].opts)
    vim.treesitter.language.register("markdown", "AgenticChat")
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_buf_set_lines(
      buf,
      0,
      -1,
      false,
      { "| Name | Kind |", "| ---- | ---- |", "| foo  | bar  |", "" }
    )
    vim.bo[buf].filetype = "AgenticChat"
    vim.treesitter.start(buf, "markdown")
    require("render-markdown").render({ buf = buf, force = true })
    -- render() draws on the next event-loop turn.
    vim.wait(1000, function()
      return #vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, {}) > 0
    end)
  end)

  after_each(function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("draws every border in the muted comment colour", function()
    local groups = border_groups()
    assert.are.same({ "RenderMarkdownTableHead", "RenderMarkdownTableRow" }, groups)
    for _, group in ipairs(groups) do
      assert.are.same({ fg = palette.comment, bold = false }, colour(group))
    end
  end)

  it("draws the header bold in the normal foreground", function()
    assert.are.same({ "@markup.heading.markdown" }, captures_at(0, 2))
    assert.are.same({ fg = colour("Normal").fg, bold = true }, colour("@markup.heading.markdown"))
  end)

  it("leaves body cells in the normal foreground", function()
    assert.are.same({}, captures_at(2, 2))
  end)
end)

describe("a write to a rendered agent chat", function()
  local buf

  before_each(function()
    vim.cmd("runtime! plugin/render-markdown.lua")
    local spec = require("plugins.render-markdown")[1]
    spec.config(nil, spec.opts)
    vim.treesitter.language.register("markdown", "AgenticChat")
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Some **bold** text.", "", "```lua", "local x = 1", "```", "" })
    vim.bo[buf].filetype = "AgenticChat"
    vim.treesitter.start(buf, "markdown")
    require("render-markdown").render({ buf = buf, force = true })
    vim.wait(1000, function()
      return vim.wo.conceallevel > 0
    end)
  end)

  after_each(function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  -- Each reparse scans the whole chat, so one per streamed or replayed write grew quadratically.
  it("leaves parsing the chat to the next redraw, though the chat is concealed", function()
    assert.is_true(vim.wo.conceallevel > 0)
    vim.cmd.redraw()
    local parser = assert(vim.treesitter.get_parser(buf))
    local parse, parses = parser.parse, 0
    parser.parse = function(...)
      parses = parses + 1
      return parse(...)
    end
    -- As agentic writes a reply: append, then keep the chat scrolled to its end.
    for i = 1, 3 do
      vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "reply line " .. i })
      vim.cmd("normal! G0zb")
    end
    parser.parse = parse
    assert.are.equal(0, parses)
  end)
end)

describe("headings and bullets in a rendered agent chat", function()
  local buf

  --- The text or concealment render-markdown draws over (0-based) `row`, from column 0.
  local function drawn_over_marker(row)
    local drawn = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, { row, 0 }, { row, 0 }, { details = true })) do
      local details = mark[4]
      if details.virt_text or details.conceal or details.sign_text then
        table.insert(drawn, details)
      end
    end
    return drawn
  end

  before_each(function()
    vim.cmd("runtime! plugin/render-markdown.lua")
    require("render-markdown").setup(require("plugins.render-markdown")[1].opts)
    vim.treesitter.language.register("markdown", "AgenticChat")
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, buf)
    -- The table's border shows when the render has landed.
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "### Title", "", "- item", "", "| a | b |", "| - | - |", "" })
    -- Off the cursor's line, which render-markdown leaves raw.
    vim.api.nvim_win_set_cursor(0, { 7, 0 })
    vim.bo[buf].filetype = "AgenticChat"
    vim.treesitter.start(buf, "markdown")
    require("render-markdown").render({ buf = buf, force = true })
    vim.wait(1000, function()
      return #vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, {}) > 0
    end)
  end)

  after_each(function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("shows the heading's ### as written", function()
    assert.are.same({}, drawn_over_marker(0))
  end)

  it("shows the bullet's - as written", function()
    assert.are.same({}, drawn_over_marker(2))
  end)
end)

describe("wrapped quotes and list items, rendered", function()
  local buf, win

  local lines = {
    "> quoted words that run on past the window edge here",
    ">",
    "> - item words that run on past the window edge here",
    "- plain item words that run on past the window edge",
    "",
  }

  --- `win`'s screen rows as drawn, trailing blanks trimmed.
  local function screen_rows()
    local pos = vim.api.nvim_win_get_position(win)
    local rows = {}
    for row = 1, vim.api.nvim_win_get_height(win) do
      local cells = {}
      for col = 1, vim.api.nvim_win_get_width(win) do
        table.insert(cells, vim.fn.screenstring(pos[1] + row, pos[2] + col))
      end
      local text = table.concat(cells):gsub("%s+$", "")
      table.insert(rows, text)
    end
    return rows
  end

  before_each(function()
    vim.cmd("runtime! plugin/render-markdown.lua")
    local spec = require("plugins.render-markdown")[1]
    spec.config(nil, spec.opts)
    vim.treesitter.language.register("markdown", "AgenticChat")
    pcall(vim.cmd, "only!")
    win = vim.api.nvim_open_win(0, true, { split = "right", width = 40 })
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    -- Off every wrapped line, which render-markdown would leave raw under the cursor.
    vim.api.nvim_win_set_cursor(win, { #lines, 0 })
  end)

  after_each(function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  --- Render `buf` as `filetype` and wait for the quote bar to land.
  local function render(filetype)
    vim.bo[buf].filetype = filetype
    vim.treesitter.start(buf, "markdown")
    require("render-markdown").render({ buf = buf, force = true })
    vim.wait(1000, function()
      return #vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, {}) > 0
    end)
    vim.cmd.redraw()
  end

  it("repeat the quote bar and hang items in an agent chat, with no wrap marker", function()
    vim.wo[win].showbreak = require("plugins.agentic")[1].opts.windows.chat.win_opts.showbreak
    render("AgenticChat")
    assert.are.same({
      "▋ quoted words that run on past the",
      "▋ window edge here",
      "▋",
      "▋ - item words that run on past the",
      "▋   window edge here",
      "- plain item words that run on past the",
      "  window edge",
    }, vim.list_slice(screen_rows(), 1, 7))
  end)

  it("repeat the quote bar over the wrap marker, and hang items, in a markdown file", function()
    render("markdown")
    assert.are.same({
      "▋ quoted words that run on past the",
      "▋ window edge here",
      "▋",
      "▋ - item words that run on past the",
      "▋   window edge here",
      "- plain item words that run on past the",
      "↪ window edge",
    }, vim.list_slice(screen_rows(), 1, 7))
  end)

  it("leave the window's own line-break options once rendering is toggled off", function()
    render("markdown")
    require("render-markdown").buf_disable()
    -- Turning rendering off lands, like rendering, on a later event-loop turn.
    vim.wait(1000, function()
      return #vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, {}) == 0
    end)
    assert.are.equal("sbr", vim.wo[win].breakindentopt)
  end)
end)
