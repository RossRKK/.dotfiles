-- Headless check that a buffer which attaches to gitsigns *after* its repo's
-- review base was chosen diffs against that base, not HEAD (plugins/git.lua
-- on_attach). Run from the dotfiles root:
--   nvim --headless -u NONE -l .config/nvim/tests/review_base_test.lua
-- Exit code 0 on pass, 1 on fail; details on stderr.

local function sh(cmd, cwd)
  local r = vim.system(cmd, { cwd = cwd, text = true }):wait()
  assert(r.code == 0, table.concat(cmd, " ") .. "\n" .. (r.stderr or ""))
  return vim.trim(r.stdout)
end

local here = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
local nvim_cfg = vim.fs.normalize(here .. "/..")
local gitsigns = vim.fn.stdpath("data") .. "/lazy/gitsigns.nvim"
local triage = vim.fs.normalize("~/dev/triage.nvim")
for _, p in ipairs({ nvim_cfg, gitsigns, triage }) do
  assert(vim.uv.fs_stat(p), "missing " .. p)
  vim.opt.rtp:prepend(p)
end

-- Repo: `main` has three lines; `topic` deletes the middle one and commits it.
-- The working file then equals HEAD, so a HEAD-based diff has zero hunks and
-- only a `main`-based diff shows the deletion.
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
sh({ "git", "init", "-q", "-b", "main" }, root)
sh({ "git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "root" }, root)
vim.fn.writefile({ "one", "two", "three" }, root .. "/f.txt")
sh({ "git", "add", "f.txt" }, root)
sh({ "git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "base" }, root)
sh({ "git", "checkout", "-q", "-b", "topic" }, root)
vim.fn.writefile({ "one", "three" }, root .. "/f.txt")
sh({ "git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-am", "drop two" }, root)

-- The real gitsigns opts from the lazy spec, so the on_attach under test is
-- the one in use.
local spec
for _, s in ipairs(require("plugins.git")) do
  if s[1] == "lewis6991/gitsigns.nvim" then
    spec = s
  end
end
assert(spec, "gitsigns spec not found in plugins.git")
require("gitsigns").setup(spec.opts)

-- Choose the review base BEFORE the buffer exists, as review mode does.
require("triage.gitsigns").set_base(root, "main")

vim.cmd.edit(root .. "/f.txt")
local buf = vim.api.nvim_get_current_buf()

local hunks
vim.wait(5000, function()
  local ok, h = pcall(require("gitsigns").get_hunks, buf)
  hunks = ok and h or nil
  return hunks ~= nil and #hunks > 0
end, 50)

local n = hunks and #hunks or 0
if n ~= 1 or hunks[1].type ~= "delete" then
  io.stderr:write(("FAIL: expected 1 delete hunk vs main, got %d (%s)\n"):format(n, vim.inspect(hunks)))
  os.exit(1)
end
io.stderr:write("PASS: buffer attached after set_base diffs against the review base\n")
os.exit(0)
