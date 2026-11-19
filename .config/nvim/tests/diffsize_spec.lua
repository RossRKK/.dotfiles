local assert = require("luassert")
local diffsize = require("util.diffsize")

describe("diffsize.parse_attrs", function()
  it("parses each path's attributes into flags and a tier", function()
    local out = table.concat({
      "a.rs\0linguist-generated\0unspecified\0",
      "a.rs\0linguist-documentation\0unspecified\0",
      "a.rs\0review-tier\0unspecified\0",
      "gen/x y.py\0linguist-generated\0true\0",
      "gen/x y.py\0linguist-documentation\0unset\0",
      "gen/x y.py\0review-tier\0proto\0",
    })
    assert.same({
      ["a.rs"] = {},
      ["gen/x y.py"] = { generated = true, documentation = false, tier = "proto" },
    }, diffsize.parse_attrs(out))
  end)

  it("drops a review-tier that names no tier", function()
    local out = "a.rs\0review-tier\0important\0"
    assert.same({ ["a.rs"] = {} }, diffsize.parse_attrs(out))
  end)

  it("is empty for empty output", function()
    assert.same({}, diffsize.parse_attrs(""))
  end)
end)

describe("diffsize.attr_input / attr_cmd", function()
  it("NUL-terminates every path, and sends nothing for no paths", function()
    assert.equals("a\0b c\0", diffsize.attr_input({ "a", "b c" }))
    assert.equals("", diffsize.attr_input({}))
  end)

  it("asks for every attribute tier() reads, from a tree only when given one", function()
    local attrs = { "linguist-generated", "linguist-documentation", "review-tier" }
    assert.same(
      vim.list_extend({ "git", "check-attr", "-z", "--stdin" }, attrs),
      diffsize.attr_cmd()
    )
    assert.same(
      vim.list_extend({ "git", "check-attr", "-z", "--stdin", "--source", "origin/main" }, attrs),
      diffsize.attr_cmd("origin/main")
    )
  end)
end)

describe("diffsize.tier", function()
  local cases = {
    { "api/v1/service.proto", "proto" },
    { "docs/foo-spec.md", "spec" },
    { "INTENT.txt", "spec" },
    { "openspec/specs/queue/spec.md", "spec" },
    { "specs/schema.proto", "proto" },
    { "lua/foo_spec.lua", "test" },
    { "tests/helpers.lua", "test" },
    { "pkg/server_test.go", "test" },
    { "app/test_views.py", "test" },
    { "web/src/__tests__/a.tsx", "test" },
    { "web/src/a.test.ts", "test" },
    { "README.md", "docs" },
    { "notes.txt", "code" },
    { "src/main.rs", "code" },
    { "testing/main.rs", "code" },
    { "Cargo.lock", "generated" },
    { "projects/web/package-lock.json", "generated" },
    { "src/Cargo.lock.rs", "code" },
  }
  for _, case in ipairs(cases) do
    it(("puts %s in %s by its path"):format(case[1], case[2]), function()
      assert.equals(case[2], diffsize.tier(case[1], nil))
    end)
  end

  it("follows linguist-generated when it is set either way", function()
    assert.equals("generated", diffsize.tier("infra/_generated/a.yaml", { generated = true }))
    assert.equals("code", diffsize.tier("Cargo.lock", { generated = false }))
    assert.equals("proto", diffsize.tier("gen/a.proto", { generated = false }))
  end)

  it("follows linguist-documentation when it is set either way", function()
    assert.equals("docs", diffsize.tier("site/guide.html", { documentation = true }))
    assert.equals("code", diffsize.tier("templates/email.md", { documentation = false }))
  end)

  it("takes review-tier over every other rule", function()
    assert.equals("code", diffsize.tier("Cargo.lock", { tier = "code" }))
    assert.equals(
      "generated",
      diffsize.tier("src/main.rs", { tier = "generated", generated = false })
    )
    assert.equals("spec", diffsize.tier("schema/openapi.yaml", { tier = "spec" }))
  end)
end)

describe("diffsize.summarize", function()
  local changes = {
    { path = "api.proto", additions = 100, deletions = 20 },
    { path = "SPEC.md", additions = 30, deletions = 5 },
    { path = "src/a.rs", additions = 300, deletions = 60 },
    { path = "src/b.rs", additions = 40, deletions = 10 },
    { path = "src/a_test.rs", additions = 250, deletions = 10 },
    { path = "README.md", additions = 9, deletions = 0 },
    { path = "Cargo.lock", additions = 9000, deletions = 400 },
  }

  it("sums each tier, untouched tiers zero", function()
    local size = diffsize.summarize(changes)
    assert.same({
      spec = { additions = 30, deletions = 5 },
      proto = { additions = 100, deletions = 20 },
      code = { additions = 340, deletions = 70 },
      test = { additions = 250, deletions = 10 },
      docs = { additions = 9, deletions = 0 },
      generated = { additions = 9000, deletions = 400 },
    }, size.tiers)
    assert.same(
      { "spec", "proto", "code", "test", "docs", "generated" },
      vim.tbl_map(function(t)
        return t.name
      end, diffsize.TIERS)
    )
  end)

  it("headlines the reviewed tiers' plain sum, generated excluded", function()
    local size = diffsize.summarize(changes)
    assert.same({ additions = 729, deletions = 105 }, diffsize.headline(size))
    assert.same({ "+729", "-105" }, { diffsize.counts(size) })
  end)

  it("moves a file between tiers by its attributes", function()
    local size = diffsize.summarize(changes, { ["Cargo.lock"] = { generated = false } })
    assert.same({ additions = 0, deletions = 0 }, size.tiers.generated)
    assert.same({ additions = 9729, deletions = 505 }, diffsize.headline(size))
  end)
end)

describe("diffsize.abbrev", function()
  it("shortens large counts", function()
    assert.equals("950", diffsize.abbrev(950))
    assert.equals("1k", diffsize.abbrev(1000))
    assert.equals("9.4k", diffsize.abbrev(9400))
    assert.equals("12k", diffsize.abbrev(12345))
    assert.equals("1.3M", diffsize.abbrev(1300000))
  end)
end)

describe("diffsize text", function()
  local size = diffsize.summarize({
    { path = "spec.md", additions = 5, deletions = 0 },
    { path = "api.proto", additions = 100, deletions = 20 },
    { path = "src/a.rs", additions = 400, deletions = 10 },
    { path = "Cargo.lock", additions = 9000, deletions = 400 },
  })

  it("legends only the touched tiers, in tier order", function()
    assert.equals(
      "**+505 -30** \u{00b7} 5 spec \u{00b7} 120 proto \u{00b7} 410 code \u{00b7} 9.4k generated",
      diffsize.markdown(size)
    )
  end)

  it("is the bare counts for an empty diff", function()
    assert.equals("**+0 -0**", diffsize.markdown(diffsize.summarize({})))
  end)
end)

describe("diffsize.bar", function()
  local function bar(changes)
    return vim.tbl_map(function(s)
      return { s.tier, s.text }
    end, diffsize.bar(diffsize.summarize(changes), 16))
  end

  it(
    "fills the bar with the reviewed tiers, in eighths of a cell, generated trailing at the same scale",
    function()
      -- 128 reviewed lines over 16 cells: a line is an eighth of a cell.
      assert.same(
        {
          { "proto", "\u{2588}\u{258c}" },
          { "code", ("\u{2588}"):rep(12) },
          { "test", "\u{2588}\u{2588}\u{258c}" },
          { "generated", ("\u{2591}"):rep(4) },
        },
        bar({
          { path = "a.proto", additions = 12, deletions = 0 },
          { path = "a.rs", additions = 92, deletions = 4 },
          { path = "a_test.go", additions = 20, deletions = 0 },
          { path = "Cargo.lock", additions = 16, deletions = 16 },
        })
      )
    end
  )

  it("caps generated at half the bar, however much it outweighs the review", function()
    assert.same(
      { { "code", ("\u{2588}"):rep(16) }, { "generated", ("\u{2591}"):rep(8) } },
      bar({
        { path = "a.rs", additions = 10, deletions = 0 },
        { path = "Cargo.lock", additions = 100000, deletions = 0 },
      })
    )
    assert.same(
      { { "generated", ("\u{2591}"):rep(8) } },
      bar({ { path = "go.sum", additions = 5, deletions = 0 } })
    )
  end)

  it("never shrinks a touched tier below its narrowest glyph", function()
    assert.same(
      { { "code", ("\u{2588}"):rep(16) }, { "test", "\u{258f}" }, { "generated", "\u{2591}" } },
      bar({
        { path = "a.rs", additions = 100000, deletions = 0 },
        { path = "a_test.go", additions = 1, deletions = 0 },
        { path = "go.sum", additions = 1, deletions = 0 },
      })
    )
  end)

  it("is empty for an empty diff", function()
    assert.same({}, bar({}))
  end)
end)

describe("diffsize.chunks", function()
  it("draws counts, bar and legend, each tier in its own highlight", function()
    local size = diffsize.summarize({
      { path = "a.rs", additions = 64, deletions = 0 },
      { path = "Cargo.lock", additions = 64, deletions = 0 },
    })
    assert.same({
      { "+64", "Added" },
      { " " },
      { "-0", "Removed" },
      { "  " },
      { ("\u{2588}"):rep(16), "DiffSizeCode" },
      { ("\u{2591}"):rep(8), "DiffSizeGenerated" },
      { "  ", "Dim" },
      { "64 code", "DiffSizeCode" },
      { " \u{00b7} ", "Dim" },
      { "64 generated", "DiffSizeGenerated" },
    }, diffsize.chunks(size, "Dim"))
  end)

  it("links each tier's group to a theme group, dimming generated", function()
    diffsize.define_highlights()
    assert.equals("Comment", vim.api.nvim_get_hl(0, { name = "DiffSizeGenerated" }).link)
    assert.equals("Function", vim.api.nvim_get_hl(0, { name = "DiffSizeCode" }).link)
    assert.equals("Special", vim.api.nvim_get_hl(0, { name = "DiffSizeSpec" }).link)
    assert.equals("Type", vim.api.nvim_get_hl(0, { name = "DiffSizeProto" }).link)
  end)
end)

describe("diffsize.by_tier", function()
  local function path(c)
    return c.path
  end

  it("groups touched tiers in tier order, files keeping their order within one", function()
    local groups = diffsize.by_tier({
      { path = "src/b.rs" },
      { path = "Cargo.lock" },
      { path = "api.proto" },
      { path = "src/a.rs" },
      { path = "src/a_test.rs" },
    }, path)
    assert.same({
      { tier = "proto", items = { { path = "api.proto" } } },
      { tier = "code", items = { { path = "src/b.rs" }, { path = "src/a.rs" } } },
      { tier = "test", items = { { path = "src/a_test.rs" } } },
      { tier = "generated", items = { { path = "Cargo.lock" } } },
    }, groups)
  end)

  it("tiers each file by its attributes", function()
    local groups = diffsize.by_tier({ { path = "a.rs" } }, path, { ["a.rs"] = { tier = "spec" } })
    assert.same({ { tier = "spec", items = { { path = "a.rs" } } } }, groups)
  end)

  it("is empty for no files", function()
    assert.same({}, diffsize.by_tier({}, path))
  end)
end)
