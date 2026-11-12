local assert = require("luassert")
local api_linter = require("util.api_linter")

local book = {
  'syntax = "proto3";',
  "",
  "package acme.library.v1;",
  "",
  'import "google/api/field_behavior.proto";',
  "",
  "message Book {",
  "  string name = 1 [(google.api.field_behavior) = IDENTIFIER];",
  "  string bookTitle = 2 [(google.api.field_behavior) = REQUIRED];",
  "}",
}

-- Writes `files` (path relative to a new temp dir -> lines) and returns that dir.
local function make_tree(files)
  local root = vim.fn.tempname()
  for path, lines in pairs(files) do
    vim.fn.mkdir(vim.fs.dirname(root .. "/" .. path), "p")
    vim.fn.writefile(lines, root .. "/" .. path)
  end
  return root
end

-- Runs the real api-linter (on PATH, its common protos linked by home-manager) with the linter's own args.
local function lint(file)
  local linter = api_linter.linter(file, api_linter.paths)
  local result = vim
    .system({ linter.cmd, unpack(linter.args) }, { cwd = linter.cwd, text = true })
    :wait()
  assert.equals(0, result.code, result.stderr)
  local by_rule = {}
  for _, d in ipairs(api_linter.parse(result.stdout)) do
    by_rule[d.code] = d
  end
  return by_rule
end

describe("api_linter.parse", function()
  it(
    "turns api-linter's 1-based, end-inclusive positions into a 0-based, end-exclusive diagnostic",
    function()
      local output = vim.json.encode({
        {
          file_path = "library/v1/book.proto",
          problems = {
            {
              message = "Fields must use lower_snake_case.",
              location = {
                start_position = { line_number = 7, column_number = 3 },
                end_position = { line_number = 7, column_number = 23 },
                path = "library/v1/book.proto",
              },
              rule_id = "core::0140::lower-snake",
              rule_doc_uri = "https://linter.aip.dev/140/lower-snake",
            },
          },
        },
      })
      assert.same({
        {
          lnum = 6,
          col = 2,
          end_lnum = 6,
          end_col = 23,
          severity = vim.diagnostic.severity.WARN,
          source = "api-linter",
          code = "core::0140::lower-snake",
          message = "Fields must use lower_snake_case.",
        },
      }, api_linter.parse(output))
    end
  )

  it("reports nothing when api-linter failed and printed no JSON", function()
    assert.same({}, api_linter.parse(""))
  end)
end)

describe("api_linter.proto_root", function()
  it("is the buf module, even inside a git checkout", function()
    local root = make_tree({ [".git/HEAD"] = {}, ["protos/buf.yaml"] = { "version: v2" } })
    assert.equals(root .. "/protos", api_linter.proto_root(root .. "/protos/library/v1/book.proto"))
  end)

  it("is the git checkout without a buf module", function()
    local root = make_tree({ [".git/HEAD"] = {} })
    assert.equals(root, api_linter.proto_root(root .. "/protos/library/v1/book.proto"))
  end)

  it("is the file's own directory outside both", function()
    local root = make_tree({})
    assert.equals(root .. "/library/v1", api_linter.proto_root(root .. "/library/v1/book.proto"))
  end)
end)

describe("api_linter.linter", function()
  it(
    "reports a camelCase field on its line, resolving google/api from the common protos",
    function()
      local root = make_tree({ ["buf.yaml"] = { "version: v2" }, ["library/v1/book.proto"] = book })
      local snake = lint(root .. "/library/v1/book.proto")["core::0140::lower-snake"]
      assert.is_not_nil(snake)
      assert.equals(8, snake.lnum)
    end
  )

  it("ignores the repo's api-linter config, so packages it opts out are still reported", function()
    local root = make_tree({
      ["buf.yaml"] = { "version: v2" },
      ["api-linter.yaml"] = {
        "- included_paths:",
        "    - library/**",
        "  disabled_rules:",
        "    - all",
      },
      ["library/v1/book.proto"] = book,
    })
    assert.is_not_nil(lint(root .. "/library/v1/book.proto")["core::0140::lower-snake"])
  end)

  it("doesn't ask for Java file options", function()
    local root = make_tree({ ["book.proto"] = book })
    for rule in pairs(lint(root .. "/book.proto")) do
      assert.is_nil(rule:match("^core::0191::java%-"), rule)
    end
  end)
end)
