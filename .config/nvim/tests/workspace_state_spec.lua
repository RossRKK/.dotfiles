-- util.workspace_state: the saved workspaces a restart brings back, with their Claude sessions.

local assert = require("luassert")

local state = require("util.workspace_state")

local A = "5acea7d5-42e4-48ab-bae8-c06adaa57027"
local B = "d19ff978-d52f-4cc4-91c4-54ec57bbc5bf"

--- Session `id` as a Claude terminal runs it.
local function term(id)
  return { id = id, client = "terminal" }
end

--- Session `id` as an agent chat runs it.
local function chat(id)
  return { id = id, client = "chat" }
end

describe("workspace_state.next_state", function()
  local cases = {
    {
      name = "merges this nvim's projects into another nvim's",
      stored = { ["/neovide/proj"] = { slot = 1, session = term(B) } },
      mine = {},
      now = { ["/term/proj"] = { slot = 1, session = chat(A) } },
      want = {
        ["/neovide/proj"] = { slot = 1, session = term(B) },
        ["/term/proj"] = { slot = 1, session = chat(A) },
      },
    },
    {
      name = "lets this nvim's save win for a project both have",
      stored = { ["/p"] = { slot = 2, session = chat(B) } },
      mine = {},
      now = { ["/p"] = { slot = 1, session = chat(A) } },
      want = { ["/p"] = { slot = 1, session = chat(A) } },
    },
    {
      name = "drops a project this nvim closed, keeping the other nvim's",
      stored = { ["/closed"] = { slot = 2, session = chat(A) }, ["/other"] = { slot = 1, session = chat(B) } },
      mine = { ["/closed"] = true, ["/kept"] = true },
      now = { ["/kept"] = { slot = 1 } },
      want = { ["/other"] = { slot = 1, session = chat(B) }, ["/kept"] = { slot = 1 } },
    },
    {
      name = "keeps the last session while the project's agent is absent",
      stored = { ["/p"] = { slot = 1, session = chat(A) } },
      mine = { ["/p"] = true },
      now = { ["/p"] = { slot = 1 } },
      want = nil,
    },
    {
      name = "takes a new session (after /clear) over the stored one",
      stored = { ["/p"] = { slot = 1, session = chat(A) } },
      mine = { ["/p"] = true },
      now = { ["/p"] = { slot = 1, session = chat(B) } },
      want = { ["/p"] = { slot = 1, session = chat(B) } },
    },
    {
      name = "takes a chat that replaced terminal 1's Claude",
      stored = { ["/p"] = { slot = 1, session = term(A) } },
      mine = { ["/p"] = true },
      now = { ["/p"] = { slot = 1, session = chat(A) } },
      want = { ["/p"] = { slot = 1, session = chat(A) } },
    },
    {
      name = "writes nothing from an nvim that never had a workspace (nested, text mode)",
      stored = { ["/p"] = { slot = 1, session = chat(A) } },
      mine = {},
      now = {},
      want = nil,
    },
    {
      name = "writes nothing when nothing changed",
      stored = { ["/p"] = { slot = 1, session = chat(A) } },
      mine = { ["/p"] = true },
      now = { ["/p"] = { slot = 1, session = chat(A) } },
      want = nil,
    },
  }
  for _, c in ipairs(cases) do
    it(c.name, function()
      assert.same(c.want, state.next_state(c.stored, c.mine, c.now))
    end)
  end
end)

describe("workspace_state.restorable", function()
  local stored = {
    ["/b"] = { slot = 2, session = chat(B) },
    ["/a"] = { slot = 3, session = term(A) },
    ["/open"] = { slot = 1 },
    ["/deleted-worktree"] = { slot = 4, session = chat(A) },
  }
  local plan = state.restorable(stored, function(dir)
    return dir == "/open"
  end, function(dir)
    return dir ~= "/deleted-worktree"
  end)

  it("reopens the projects not open here, in workspace-number order", function()
    assert.same(
      { { dir = "/b", slot = 2, session = chat(B) }, { dir = "/a", slot = 3, session = term(A) } },
      plan.open
    )
  end)

  it("skips a project whose directory is gone and reports it", function()
    assert.same({ "/deleted-worktree" }, plan.gone)
  end)
end)

describe("workspace_state on disk", function()
  local dir, file, projects, real_fishmonger, real_agent_chat, real_workspace_open

  --- A workspace tabpage on `path` numbered `slot`, as config.workspace makes one.
  local function workspace_tab(path, slot)
    vim.cmd("tabnew")
    vim.cmd("tcd " .. vim.fn.fnameescape(path))
    vim.api.nvim_tabpage_set_var(0, "workspace_slot", slot)
    return vim.api.nvim_get_current_tabpage()
  end

  local function stored()
    return vim.json.decode(table.concat(vim.fn.readfile(file), "\n"))
  end

  local function write(projects_by_dir)
    vim.fn.mkdir(vim.fs.dirname(file), "p")
    vim.fn.writefile({ vim.json.encode(projects_by_dir) }, file)
  end

  -- tabpage -> the session id terminal 1's agent reports; chats -> the ids agent chats host.
  local sessions, chats = {}, {}

  before_each(function()
    dir = vim.fn.resolve(vim.fn.tempname())
    for _, p in ipairs({ "/one", "/two", "/claude/projects/-one" }) do
      vim.fn.mkdir(dir .. p, "p")
    end
    file = dir .. "/state/workspaces.json"
    projects = dir .. "/claude/projects"
    sessions, chats = {}, {}
    real_fishmonger = package.loaded["fishmonger"]
    real_agent_chat = package.loaded["config.agent_chat"]
    package.loaded["fishmonger"] = {
      tabs = function(tab)
        local id = sessions[tab]
        return id and { { slot = 1, agent = { session = id } } } or {}
      end,
    }
    package.loaded["config.agent_chat"] = {
      hosts = function(id)
        return chats[id] == true
      end,
    }
    state.setup({ file = file, claude_projects = projects })
  end)

  after_each(function()
    vim.cmd("tabfirst | silent! tabonly")
    vim.wait(20)
    pcall(vim.api.nvim_del_augroup_by_name, "workspace_state")
    package.loaded["fishmonger"] = real_fishmonger
    package.loaded["config.agent_chat"] = real_agent_chat
    local workspace = require("config.workspace")
    workspace.open = real_workspace_open or workspace.open
    vim.fn.delete(dir, "rf")
  end)

  it("saves each workspace's directory, number and terminal 1's session, with what runs it", function()
    sessions[workspace_tab(dir .. "/one", 1)] = A
    chats[A] = true
    sessions[workspace_tab(dir .. "/two", 2)] = B
    state.save()
    assert.same({
      [dir .. "/one"] = { slot = 1, session = chat(A) },
      [dir .. "/two"] = { slot = 2, session = term(B) },
    }, stored())
  end)

  it("writes no file from an nvim without workspaces", function()
    state.save()
    assert.equals(0, vim.fn.filereadable(file))
  end)

  it("drops a workspace closed on purpose", function()
    workspace_tab(dir .. "/one", 1)
    workspace_tab(dir .. "/two", 2)
    state.save()
    vim.cmd("tabclose")
    state.save()
    assert.same({ [dir .. "/one"] = { slot = 1 } }, stored())
  end)

  it("keeps every workspace once nvim is exiting", function()
    workspace_tab(dir .. "/one", 1)
    workspace_tab(dir .. "/two", 2)
    vim.api.nvim_exec_autocmds("VimLeavePre", { group = "workspace_state" })
    vim.cmd("tabclose")
    state.save()
    assert.same({ [dir .. "/one"] = { slot = 1 }, [dir .. "/two"] = { slot = 2 } }, stored())
  end)

  it("keeps a session whose agent died before nvim did", function()
    local tab = workspace_tab(dir .. "/one", 1)
    sessions[tab] = A
    chats[A] = true
    state.save()
    sessions[tab] = nil
    state.save()
    assert.same({ [dir .. "/one"] = { slot = 1, session = chat(A) } }, stored())
  end)

  it("reads a session saved as a bare id as a Claude terminal's", function()
    write({ [dir .. "/one"] = { slot = 1, session = A } })
    local tab = workspace_tab(dir .. "/two", 2)
    sessions[tab] = B
    state.save()
    assert.same({
      [dir .. "/one"] = { slot = 1, session = term(A) },
      [dir .. "/two"] = { slot = 2, session = term(B) },
    }, stored())
  end)

  it("drops a session it cannot read", function()
    write({ [dir .. "/one"] = { slot = 1, session = { id = A, client = "tmux" } } })
    sessions[workspace_tab(dir .. "/two", 2)] = B
    state.save()
    assert.same({ slot = 1 }, stored()[dir .. "/one"])
  end)

  describe("restore", function()
    local opened

    before_each(function()
      local workspace = require("config.workspace")
      real_workspace_open = workspace.open
      opened = {}
      workspace.open = function(path, opts)
        opened[#opened + 1] = { dir = path, resume = opts.resume, slot = opts.slot }
      end
      write({
        [dir .. "/one"] = { slot = 1, session = chat(A) },
        [dir .. "/two"] = { slot = 2, session = B },
        [dir .. "/gone"] = { slot = 3, session = chat(A) },
      })
      vim.fn.writefile({}, projects .. "/-one/" .. A .. ".jsonl")
    end)

    it("resumes a session with a transcript, as what ran it, and opens one without fresh", function()
      state.restore()
      assert.same({
        { dir = dir .. "/one", slot = 1, resume = chat(A) },
        { dir = dir .. "/two", slot = 2 },
      }, opened)
    end)

    it("drops a project whose directory is gone from the file", function()
      state.restore()
      assert.is_nil(stored()[dir .. "/gone"])
      assert.is_not_nil(stored()[dir .. "/two"])
    end)
  end)
end)
