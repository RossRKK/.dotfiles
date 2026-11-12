local assert = require("luassert")
local api_linter = require("util.api_linter")

-- A repo laid out like one whose hook runs api-linter from its proto root: the
-- config there, one package linted and one opted out through included_paths.
local function make_repo()
  local root = vim.fn.tempname()
  local proto = table.concat({
    'syntax = "proto3";',
    "",
    "package acme.library.v1;",
    "",
    "message Book {",
    "  string name = 1;",
    "  string bookTitle = 2;",
    "}",
  }, "\n") .. "\n"
  for _, dir in ipairs({ "library/v1", "legacy/v1" }) do
    vim.fn.mkdir(root .. "/protos/" .. dir, "p")
    vim.fn.writefile(vim.split(proto, "\n"), root .. "/protos/" .. dir .. "/book.proto")
  end
  vim.fn.writefile({
    "- included_paths:",
    "    - legacy/**",
    "  disabled_rules:",
    "    - all",
  }, root .. "/protos/api-linter.yaml")
  return root
end

local function run(file)
  local linter = api_linter.linter(assert(api_linter.find_config(file)), file)
  local result = vim
    .system({ linter.cmd, unpack(linter.args) }, { cwd = linter.cwd, text = true })
    :wait()
  assert.equals(0, result.code, result.stderr)
  return api_linter.parse(result.stdout)
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

describe("api_linter.find_config", function()
  it("finds the nearest config above the file", function()
    local root = make_repo()
    assert.equals(
      root .. "/protos/api-linter.yaml",
      api_linter.find_config(root .. "/protos/library/v1/book.proto")
    )
  end)

  it("finds nothing outside a repo with a config", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    assert.is_nil(api_linter.find_config(dir .. "/book.proto"))
  end)
end)

-- Runs the real api-linter (on PATH via home-manager) with the linter's own args.
describe("api_linter.linter", function()
  it("reports a camelCase field on its line", function()
    local root = make_repo()
    local by_rule = {}
    for _, d in ipairs(run(root .. "/protos/library/v1/book.proto")) do
      by_rule[d.code] = d
    end
    local snake = by_rule["core::0140::lower-snake"]
    assert.is_not_nil(snake, vim.inspect(by_rule))
    assert.equals(6, snake.lnum)
  end)

  it("names the file relative to the config, so its included_paths apply", function()
    local root = make_repo()
    assert.same({}, run(root .. "/protos/legacy/v1/book.proto"))
  end)
end)
