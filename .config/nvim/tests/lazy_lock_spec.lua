local assert = require("luassert")

-- Machines without ~/dev checkouts restore these from the lockfile; a dev
-- machine's lazy drops them on every rewrite, so guard against committing that.
describe("lazy-lock.json", function()
  local config = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
  local lock = vim.json.decode(table.concat(vim.fn.readfile(config .. "/lazy-lock.json"), "\n"))

  for _, name in ipairs({ "agentic.nvim", "fishmonger.nvim", "nitpick.nvim", "triage.nvim" }) do
    it("pins the dev plugin " .. name, function()
      assert.is_table(lock[name])
      assert.matches("^%x+$", lock[name].commit)
    end)
  end
end)
