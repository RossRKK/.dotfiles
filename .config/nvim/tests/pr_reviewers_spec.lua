-- A PR's reviewers, as GitHub's Reviewers panel lists them, from recorded
-- `gh api graphql` replies (names changed).

local assert = require("luassert")
local pr_reviewers = require("util.pr_reviewers")

--- A recorded reply by its case name.
local function recorded(case)
  local path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
    .. "/fixtures/pr_reviewers.json"
  return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))[case]
end

--- A reply from requests ({ login, code owner }) and reviews ({ login, state }), by `author`.
local function reply(author, requests, reviews)
  return {
    data = {
      repository = {
        pullRequest = {
          author = { login = author },
          reviewRequests = {
            nodes = vim.tbl_map(function(r)
              return {
                asCodeOwner = r[2],
                requestedReviewer = { __typename = "User", login = r[1] },
              }
            end, requests),
          },
          latestReviews = {
            nodes = vim.tbl_map(function(r)
              return { state = r[2], author = { login = r[1] }, onBehalfOf = { nodes = {} } }
            end, reviews),
          },
        },
      },
    },
  }
end

--- Reviewers as "name kind state" strings, code owners starred.
local function brief(reviewers)
  return vim.tbl_map(function(r)
    return ("%s%s %s %s"):format(r.name, r.code_owner and "*" or "", r.kind, r.state)
  end, reviewers)
end

describe("pr_reviewers.parse", function()
  it(
    "lists requested teams and users pending, code owners marked, then unrequested reviews",
    function()
      local reviewers = pr_reviewers.parse(recorded("teams_and_an_unrequested_review"))
      assert.same({
        "acme/physics* team pending",
        "acme/runtime* team pending",
        "bob user pending",
        "carol user pending",
        "dave user approved",
      }, brief(reviewers))
      assert.same({ "acme/devs", "acme/orchestrator" }, reviewers[5].on_behalf_of)
      assert.same({}, reviewers[1].on_behalf_of)
    end
  )

  it("lists a team's auto-assigned member as a request of its own", function()
    assert.same({
      "acme/platform* team pending",
      "frank user pending",
      "claude user commented",
    }, brief(pr_reviewers.parse(recorded("team_and_its_auto_assigned_member"))))
  end)

  it("reads each submitted review's state", function()
    assert.same(
      { "a user approved", "b user changes_requested", "c user commented" },
      brief(pr_reviewers.parse(reply("me", {}, {
        { "a", "APPROVED" },
        { "b", "CHANGES_REQUESTED" },
        { "c", "COMMENTED" },
      })))
    )
  end)

  it("keeps a reviewer requested again pending, once", function()
    assert.same(
      { "a user pending" },
      brief(pr_reviewers.parse(reply("me", { { "a", false } }, { { "a", "APPROVED" } })))
    )
  end)

  it("leaves out the author's own reviews, drafts and dismissed reviews", function()
    assert.same(
      {},
      brief(pr_reviewers.parse(reply("me", {}, {
        { "me", "COMMENTED" },
        { "a", "PENDING" },
        { "b", "DISMISSED" },
      })))
    )
  end)
end)
