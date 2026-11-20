-- The PR stack around a branch, from my open PRs as the review queue parses them.

local assert = require("luassert")
local pr_stack = require("util.pr_stack")
local rq = require("util.reviewqueue")

local repo = { owner = "acme", name = "mono" }

--- Recorded `gh api graphql` PR nodes (names changed), as the queue's items.
local function recorded()
  local path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
    .. "/fixtures/pr_stack_nodes.json"
  local nodes = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
  return vim.tbl_map(function(node)
    return { pr = rq.from_node(node, false, repo), verdict = { tier = 5, reason = "waiting" } }
  end, nodes)
end

--- Items from { number, head, base } triples.
local function items(specs)
  return vim.tbl_map(function(s)
    return {
      pr = { number = s[1], head = s[2], base = s[3] },
      verdict = { tier = 5, reason = "waiting" },
    }
  end, specs)
end

---@param stack pr_stack.Stack?
local function numbers(stack)
  return stack and vim.tbl_map(function(r)
    return r.pr.number
  end, stack.rows)
end

describe("pr_stack.of", function()
  it("orders a recorded stack top first, down to the trunk", function()
    local stack = pr_stack.of(recorded(), "rkk/git-api-deploy")
    assert.same({ 8865, 8909, 8839 }, numbers(stack))
    assert.equals("master", stack.trunk)
  end)

  it("marks only the checked-out branch's PR current", function()
    local stack = assert(pr_stack.of(recorded(), "rkk/git-api-deploy"))
    assert.same(
      { false, true, false },
      vim.tbl_map(function(r)
        return r.current
      end, stack.rows)
    )
  end)

  it("carries the parsed draft and checks state through", function()
    local top = assert(pr_stack.of(recorded(), "rk/git-api")).rows[1]
    assert.is_true(top.pr.draft)
    assert.equals("PENDING", top.pr.checks)
  end)

  it("finds the same stack from any branch in it", function()
    for _, branch in ipairs({ "rk/git-api", "rkk/git-api-deploy", "rkk/workers-ui" }) do
      assert.same({ 8865, 8909, 8839 }, numbers(pr_stack.of(recorded(), branch)))
    end
  end)

  it("is nil for a PR stacked with nothing", function()
    assert.is_nil(pr_stack.of(recorded(), "rkk/rig-maintenance"))
  end)

  it("is nil for a branch without a PR, the default branch included", function()
    assert.is_nil(pr_stack.of(recorded(), "master"))
    assert.is_nil(pr_stack.of(recorded(), "rkk/local-only"))
    assert.is_nil(pr_stack.of(recorded(), nil))
  end)

  it("keeps a fork's branches together, newest above, each over its base", function()
    local stack = pr_stack.of(
      items({ { 1, "a", "main" }, { 2, "b", "a" }, { 3, "c", "a" }, { 4, "d", "b" } }),
      "c"
    )
    assert.same({ 3, 4, 2, 1 }, numbers(stack))
  end)

  it("stops at a base cycle rather than looping", function()
    local found = numbers(pr_stack.of(items({ { 1, "a", "b" }, { 2, "b", "a" } }), "a"))
    table.sort(found)
    assert.same({ 1, 2 }, found)
  end)
end)
