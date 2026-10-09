local assert = require("luassert")
local diffsize = require("util.diffsize")

describe("diffsize.parse_attrs", function()
  it("reads path/attr/value triples from check-attr -z output", function()
    local out = "a.rs\0linguist-generated\0unspecified\0gen/x y.py\0linguist-generated\0true\0"
    assert.same({ ["a.rs"] = "unspecified", ["gen/x y.py"] = "true" }, diffsize.parse_attrs(out))
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

  it("reads attributes from a tree only when given one", function()
    assert.same({ "git", "check-attr", "-z", "--stdin", "linguist-generated" }, diffsize.attr_cmd())
    assert.same(
      { "git", "check-attr", "-z", "--stdin", "--source", "origin/main", "linguist-generated" },
      diffsize.attr_cmd("origin/main")
    )
  end)
end)

describe("diffsize.is_generated", function()
  it("follows linguist-generated when it is set either way", function()
    assert.is_true(diffsize.is_generated("infra/_generated/a.yaml", "true"))
    assert.is_true(diffsize.is_generated("x", "set"))
    assert.is_false(diffsize.is_generated("Cargo.lock", "false"))
    assert.is_false(diffsize.is_generated("Cargo.lock", "unset"))
  end)

  it("counts lockfiles as generated at any depth unless told otherwise", function()
    assert.is_true(diffsize.is_generated("Cargo.lock", "unspecified"))
    assert.is_true(diffsize.is_generated("projects/web/package-lock.json", nil))
    assert.is_false(diffsize.is_generated("src/Cargo.lock.rs", nil))
    assert.is_false(diffsize.is_generated("src/main.rs", "unspecified"))
  end)
end)

describe("diffsize.summarize", function()
  local changes = {
    { path = "src/a.rs", additions = 10, deletions = 2 },
    { path = "src/b.rs", additions = 5, deletions = 0 },
    { path = "Cargo.lock", additions = 3000, deletions = 40 },
    { path = "gen/schema.json", additions = 200, deletions = 100 },
  }

  it("keeps generated files out of the totals, counted apart", function()
    local size = diffsize.summarize(changes, { ["gen/schema.json"] = "true" })
    assert.same({
      additions = 15,
      deletions = 2,
      files = 2,
      generated = { additions = 3200, deletions = 140, files = 2 },
    }, size)
  end)

  it("still knows lockfiles without any attributes", function()
    local size = diffsize.summarize(changes)
    assert.equals(3, size.files)
    assert.equals(1, size.generated.files)
  end)
end)

describe("diffsize.chunks", function()
  local function text(size)
    return table.concat(vim.tbl_map(function(c)
      return c[1]
    end, diffsize.chunks(size, "Dim")))
  end
  local none = { additions = 0, deletions = 0, files = 0 }

  it("reads +adds -dels in N files", function()
    assert.equals(
      "+12 -3 in 1 file",
      text({ additions = 12, deletions = 3, files = 1, generated = none })
    )
  end)

  it("says how many generated files it left out", function()
    local gen = { additions = 9, deletions = 9, files = 2 }
    assert.equals(
      "+12 -3 in 4 files \u{00b7} 2 generated excluded",
      text({ additions = 12, deletions = 3, files = 4, generated = gen })
    )
  end)
end)
