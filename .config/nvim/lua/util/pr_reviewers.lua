-- A PR's reviewers as GitHub's Reviewers panel lists them: who is requested
-- (CODEOWNERS requests marked), then who reviewed without a request, each
-- with their latest state. GraphQL rather than `gh pr view --json
-- reviewRequests`, which leaves out asCodeOwner.
--
-- A team member that team auto-assign picked is a user request of its own:
-- neither the request nor its ReviewRequestedEvent names the team. Only a
-- submitted review names the teams it was for (onBehalfOf).

local M = {}

M.QUERY = [[
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      author { login }
      reviewRequests(first: 50) {
        nodes {
          asCodeOwner
          requestedReviewer {
            __typename
            ... on User { login }
            ... on Bot { login }
            ... on Mannequin { login }
            ... on Team { combinedSlug }
          }
        }
      }
      latestReviews(first: 50) {
        nodes { state author { login } onBehalfOf(first: 10) { nodes { combinedSlug } } }
      }
    }
  }
}]]

---@alias pr_reviewers.State "pending"|"commented"|"approved"|"changes_requested"

---@class pr_reviewers.Reviewer
---@field name string a login, or a team's org/slug
---@field kind "user"|"team"
---@field code_owner boolean requested by CODEOWNERS
---@field state pr_reviewers.State
---@field on_behalf_of string[] the teams a submitted review was for

-- Submitted review states; drafts (PENDING) and dismissed reviews aren't shown.
local REVIEW_STATES = {
  APPROVED = "approved",
  CHANGES_REQUESTED = "changes_requested",
  COMMENTED = "commented",
}

--- The reviewers in a reply to M.QUERY: requests first, pending, then
--- reviewers nobody requested. A reviewer requested again stays pending; the
--- author's own reviews are left out.
---@param reply table the decoded `gh api graphql` reply
---@return pr_reviewers.Reviewer[]
function M.parse(reply)
  local pr = reply.data.repository.pullRequest
  local reviewers, listed = {}, {}
  for _, request in ipairs(pr.reviewRequests.nodes) do
    local who = request.requestedReviewer
    local name = who and (who.combinedSlug or who.login)
    if name then
      listed[name] = true
      reviewers[#reviewers + 1] = {
        name = name,
        kind = who.__typename == "Team" and "team" or "user",
        code_owner = request.asCodeOwner == true,
        state = "pending",
        on_behalf_of = {},
      }
    end
  end
  local author = pr.author and pr.author.login
  for _, review in ipairs(pr.latestReviews.nodes) do
    local login = review.author and review.author.login
    local state = REVIEW_STATES[review.state]
    if login and state and login ~= author and not listed[login] then
      listed[login] = true
      reviewers[#reviewers + 1] = {
        name = login,
        kind = "user",
        code_owner = false,
        state = state,
        on_behalf_of = vim.tbl_map(function(team)
          return team.combinedSlug
        end, review.onBehalfOf and review.onBehalfOf.nodes or {}),
      }
    end
  end
  return reviewers
end

return M
