-- Workspace tabs opened together, or by restore, come out like one opened by hand.
-- Drives a child nvim with the whole config on a pty, so the start screen, edgy, neo-tree and lualine are the real ones.

local assert = require("luassert")

local probe = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
  .. "/helpers/workspace_probe.lua"

local root, job, ch

--- Run `code` in the child with `...`, returning its result.
---@param code string a Lua chunk; `P` is the probe module
local function child(code, ...)
  return vim.fn.rpcrequest(
    ch,
    "nvim_exec_lua",
    "local P = dofile(" .. vim.inspect(probe) .. ")\n" .. code,
    { ... }
  )
end

--- A git repo at `root/<name>`.
---@param name string
---@return string
local function repo(name)
  local dir = root .. "/" .. name
  vim.system({ "git", "init", "-q", dir }):wait()
  vim.system({ "git", "-C", dir, "commit", "-q", "--allow-empty", "-m", "init" }):wait()
  return dir
end

--- Saved workspaces for the child to restore, numbered in order.
---@param dirs string[]
---@param sessions? table<string, any> dir -> its terminal 1 session, as a workspaces.json has it
local function save(dirs, sessions)
  local projects = {}
  for i, dir in ipairs(dirs) do
    projects[dir] = { slot = i, session = (sessions or {})[dir] }
  end
  vim.fn.mkdir(root .. "/state/nvim", "p")
  vim.fn.writefile({ vim.json.encode(projects) }, root .. "/state/nvim/workspaces.json")
end

--- Start a child nvim on its start screen, with no Claude in its terminals.
local function start()
  local sock, listening = root .. "/nvim.sock", root .. "/listening"
  job = vim.fn.jobstart({
    "env",
    "-u",
    "NVIM",
    "-u",
    "AGENT_WORKTREES",
    "-u",
    "TMUX",
    "XDG_STATE_HOME=" .. root .. "/state",
    "CLAUDE_CONFIG_DIR=" .. root .. "/claude",
    "nvim",
    "--listen",
    sock,
    -- The socket file exists from bind(), before listen(); --cmd runs only once the server accepts.
    "--cmd",
    "call writefile([], " .. vim.fn.string(listening) .. ")",
  }, { pty = true, width = 160, height = 48, cwd = root, env = { TERM = "xterm-256color" } })
  assert.is_true(vim.wait(10000, function()
    return vim.uv.fs_stat(listening) ~= nil
  end, 20))
  ch = vim.fn.sockconnect("pipe", sock, { rpc = true })
  assert.is_true(vim.wait(10000, function()
    return child("return Snacks ~= nil and Snacks.dashboard.status.opened")
  end, 20))
  child("P.stub_claude()")
end

--- Enter workspace tab `n` and read its layout and statusline once it is built.
---@param n integer
---@return { shape: string, statusline: { rows: integer[], bottom: integer } }
local function visit(n)
  child("vim.api.nvim_set_current_tabpage(P.workspaces()[...])", n)
  vim.wait(5000, function()
    return child("return P.built(P.workspaces()[...])", n)
  end, 50)
  vim.wait(5000, function()
    return #child("return P.statusline().rows") > 0
  end, 50)
  return {
    shape = child("return P.shape(P.workspaces()[...])", n),
    statusline = child("return P.statusline()"),
  }
end

--- Every workspace tab, visited in turn.
---@return table[]
local function visit_all()
  local seen = {}
  for n = 1, #child("return P.workspaces()") do
    seen[n] = visit(n)
  end
  return seen
end

--- What the start screen's Projects entry does.
---@param dir string
local function open_from_start_screen(dir)
  child("require('config.workspace').open(..., { drop_buf = vim.api.nvim_get_current_buf() })", dir)
end

--- One project opened by hand from the start screen: the layout every workspace tab should have.
---@return { shape: string, statusline: { rows: integer[], bottom: integer } }
local function by_hand()
  start()
  open_from_start_screen(repo("hand"))
  local tab = visit(1)
  vim.fn.jobstop(job)
  return tab
end

describe("a workspace tab", function()
  local want

  before_each(function()
    root = vim.fs.normalize(vim.fn.resolve(vim.fn.tempname()))
    vim.fn.mkdir(root, "p")
    want = want or by_hand()
  end)

  after_each(function()
    pcall(vim.fn.jobstop, job)
    vim.fn.delete(root, "rf")
  end)

  --- Each visited tab laid out as `want`, with the one statusline at the bottom of the screen.
  ---@param seen table[]
  ---@param count integer
  local function assert_like_by_hand(seen, count)
    local expected, got = {}, {}
    for n = 1, count do
      expected[n] = { shape = want.shape, statusline_rows = { want.statusline.bottom } }
    end
    for n, tab in ipairs(seen) do
      got[n] = { shape = tab.shape, statusline_rows = tab.statusline.rows }
    end
    assert.same(expected, got)
  end

  it("opened by hand from the start screen has its statusline at the bottom", function()
    assert.same({ want.statusline.bottom }, want.statusline.rows)
  end)

  it(
    "has its greeter and todo split replaced by a file opened from neo-tree after visiting the split",
    function()
      local dir = repo("files")
      local readme = dir .. "/README.md"
      vim.fn.writefile({ "hello" }, readme)
      start()
      open_from_start_screen(dir)
      visit(1)
      child(
        "local todo = require('config.todo'); vim.api.nvim_set_current_win(todo.window(0, todo.FILE))"
      )
      assert.is_true(vim.wait(5000, function()
        return child("return P.tree_with(...) ~= nil", readme)
      end, 50))
      child("P.open_from_tree(...)", readme)
      local file_only = want.shape:gsub("col%[snacks_dashboard, markdown%]", "markdown")
      vim.wait(5000, function()
        return child("return P.shape(0)") == file_only
      end, 50)
      assert.same(
        { shape = file_only, main = readme },
        child(
          "return { shape = P.shape(0), main = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(require('config.windows').main_window())) }"
        )
      )
    end
  )

  it(
    "restored with the start screen's s, its tab and the background ones, is laid out as by hand",
    function()
      save({ repo("one"), repo("two"), repo("three") })
      start()
      child("vim.api.nvim_input('s')")
      assert.is_true(vim.wait(5000, function()
        return #child("return P.workspaces()") == 3
      end, 50))
      assert_like_by_hand(visit_all(), 3)
    end
  )

  it("restored with the start screen's s resumes each saved session as an agent chat", function()
    local A, B = "5acea7d5-42e4-48ab-bae8-c06adaa57027", "d19ff978-d52f-4cc4-91c4-54ec57bbc5bf"
    local one, two = repo("one"), repo("two")
    -- A bare id, as files from before agent chats have it, and one saved with the client it ran in.
    save({ one, two }, { [one] = A, [two] = { id = B, client = "terminal" } })
    vim.fn.mkdir(root .. "/claude/projects/-p", "p")
    for _, id in ipairs({ A, B }) do
      vim.fn.writefile({}, root .. "/claude/projects/-p/" .. id .. ".jsonl")
    end
    start()
    child("vim.api.nvim_input('s')")
    local chats = function()
      return child("return vim.tbl_map(P.chat, P.workspaces())")
    end
    vim.wait(5000, function()
      local started = chats()
      return #started == 2 and started[1] ~= vim.NIL and started[2] ~= vim.NIL
    end, 50)
    assert.same({ { session = A }, { session = B } }, chats())
  end)

  it("restored with :WorkspaceRestore from a workspace tab is laid out as by hand", function()
    local first = repo("first")
    save({ repo("one"), repo("two") })
    start()
    open_from_start_screen(first)
    visit(1)
    child("vim.cmd('WorkspaceRestore')")
    assert_like_by_hand(visit_all(), 3)
  end)

  it("opened in one burst with the last left current is laid out as by hand", function()
    local first, dirs = repo("first"), { repo("one"), repo("two"), repo("three") }
    start()
    open_from_start_screen(first)
    visit(1)
    child(
      "for _, dir in ipairs(...) do require('config.workspace').open(dir, { tab = true }) end",
      dirs
    )
    assert_like_by_hand(visit_all(), 4)
  end)

  it(
    "keeps an agent chat's prompt height when Ctrl+B Z put it over the todo split, which then closes",
    function()
      start()
      open_from_start_screen(repo("chat"))
      visit(1)
      -- Wide enough that Ctrl+B Z takes the editor, the widest window, rather than the prompt.
      vim.fn.jobresize(job, 240, 48)
      assert.is_true(vim.wait(5000, function()
        return child("return vim.o.columns") == 240
      end, 20))
      child("P.stand_in_agent(); require('config.agent_chat').new(0)")
      assert.is_true(vim.wait(5000, function()
        return child("return P.prompt_height()") ~= vim.NIL
      end, 20))
      local opened = child("return P.prompt_height()")
      child("P.focus_chat(); require('fishmonger').maximise()")
      child("local todo = require('config.todo'); todo.toggle(todo.FILE)")
      vim.wait(1000, function()
        return child("return P.prompt_height()") == opened
      end, 20)
      assert.same(opened, child("return P.prompt_height()"))
    end
  )
end)
