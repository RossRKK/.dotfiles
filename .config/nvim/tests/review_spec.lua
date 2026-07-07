-- Tests for the review/ plugin's pure logic.
--
-- Dependency-free: run under headless Neovim, no plenary/busted needed.
--   nvim --headless -u NONE -l tests/review_spec.lua
-- (or `make test` from ~/.config/nvim). Exits non-zero on any failure, so it
-- drops straight into CI or a pre-push hook.

-- Make the config's lua/ importable regardless of the cwd nvim was launched in.
vim.opt.runtimepath:append(vim.fn.expand("~/.config/nvim"))

local passed, failed = 0, 0

---@param name string
---@param got any
---@param want any
local function eq(name, got, want)
  if got == want then
    passed = passed + 1
    print(("  ok   %s"):format(name))
  else
    failed = failed + 1
    print(("  FAIL %s  (got %s, want %s)"):format(name, vim.inspect(got), vim.inspect(want)))
  end
end

-- ---------------------------------------------------------------------------
-- review.verdict(): the review event inferred from the triage state. The whole
-- batched-submit flow leans on this, so pin every branch of the reduction.
-- ---------------------------------------------------------------------------
local review = require("review.init")

---@param state table<string, string> abs-path -> status
---@return string?
local function verdict_of(state)
  review.status_by_path = state
  return review.verdict()
end

print("review.verdict()")
eq("no changes -> nil", verdict_of({}), nil)
eq("all approved -> APPROVE", verdict_of({ a = "approved", b = "approved" }), "APPROVE")
eq("lone rejection -> REQUEST_CHANGES", verdict_of({ a = "rejected" }), "REQUEST_CHANGES")
eq("approved + rejected -> REQUEST_CHANGES", verdict_of({ a = "approved", b = "rejected" }), "REQUEST_CHANGES")
-- The mid-review property: while anything's still untriaged, a rejection does
-- NOT harden into a blocking verdict — an early submit goes out as COMMENT.
eq("changed + rejected -> COMMENT (mid-review)", verdict_of({ a = "changed", b = "rejected" }), "COMMENT")
eq("approved + changed -> COMMENT", verdict_of({ a = "approved", b = "changed" }), "COMMENT")
eq("revised counts as pending -> COMMENT", verdict_of({ a = "revised" }), "COMMENT")
eq("revised outranks rejection -> COMMENT", verdict_of({ a = "revised", b = "rejected" }), "COMMENT")

-- ---------------------------------------------------------------------------
-- Module API smoke test: the comments module loads and exposes the surface the
-- keymaps/commands bind to. Guards against a require-time break or a rename.
-- ---------------------------------------------------------------------------
print("review.comments API")
local comments = require("review.comments")
for _, fn in ipairs({ "comment", "reply", "edit", "discard_draft", "submit", "set_shown", "refresh", "has_comments" }) do
  eq(("exposes %s()"):format(fn), type(comments[fn]), "function")
end

-- ---------------------------------------------------------------------------
print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
  os.exit(1)
end
