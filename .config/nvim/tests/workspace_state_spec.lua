-- util.workspace_state: the saved workspaces a restart brings back, with their Claude sessions.

local assert = require("luassert")

local state = require("util.workspace_state")

local A = "5acea7d5-42e4-48ab-bae8-c06adaa57027"
local B = "d19ff978-d52f-4cc4-91c4-54ec57bbc5bf"

describe("workspace_state.next_state", function()
  local cases = {
    {
      name = "merges this nvim's projects into another nvim's",
      stored = { ["/neovide/proj"] = { slot = 1, session = B } },
      mine = {},
      now = { ["/term/proj"] = { slot = 1, session = A } },
      want = {
        ["/neovide/proj"] = { slot = 1, session = B },
        ["/term/proj"] = { slot = 1, session = A },
      },
    },
    {
      name = "lets this nvim's save win for a project both have",
      stored = { ["/p"] = { slot = 2, session = B } },
      mine = {},
      now = { ["/p"] = { slot = 1, session = A } },
      want = { ["/p"] = { slot = 1, session = A } },
    },
    {
      name = "drops a project this nvim closed, keeping the other nvim's",
      stored = { ["/closed"] = { slot = 2, session = A }, ["/other"] = { slot = 1, session = B } },
      mine = { ["/closed"] = true, ["/kept"] = true },
      now = { ["/kept"] = { slot = 1 } },
      want = { ["/other"] = { slot = 1, session = B }, ["/kept"] = { slot = 1 } },
    },
    {
      name = "keeps the last session id while the project's agent is absent",
      stored = { ["/p"] = { slot = 1, session = A } },
      mine = { ["/p"] = true },
      now = { ["/p"] = { slot = 1 } },
      want = nil,
    },
    {
      name = "takes a new session id (after /clear) over the stored one",
      stored = { ["/p"] = { slot = 1, session = A } },
      mine = { ["/p"] = true },
      now = { ["/p"] = { slot = 1, session = B } },
      want = { ["/p"] = { slot = 1, session = B } },
    },
    {
      name = "writes nothing from an nvim that never had a workspace (nested, text mode)",
      stored = { ["/p"] = { slot = 1, session = A } },
      mine = {},
      now = {},
      want = nil,
    },
    {
      name = "writes nothing when nothing changed",
      stored = { ["/p"] = { slot = 1, session = A } },
      mine = { ["/p"] = true },
      now = { ["/p"] = { slot = 1, session = A } },
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
    ["/b"] = { slot = 2, session = B },
    ["/a"] = { slot = 3, session = A },
    ["/open"] = { slot = 1 },
    ["/deleted-worktree"] = { slot = 4, session = A },
  }
  local plan = state.restorable(stored, function(dir)
    return dir == "/open"
  end, function(dir)
    return dir ~= "/deleted-worktree"
  end)

  it("reopens the projects not open here, in workspace-number order", function()
    assert.same(
      { { dir = "/b", slot = 2, session = B }, { dir = "/a", slot = 3, session = A } },
      plan.open
    )
  end)

  it("skips a project whose directory is gone and reports it", function()
    assert.same({ "/deleted-worktree" }, plan.gone)
  end)
end)

describe("workspace_state on disk", function()
  local dir, file, projects, real_fishmonger, real_workspace_open

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

  local sessions = {}

  before_each(function()
    dir = vim.fn.resolve(vim.fn.tempname())
    for _, p in ipairs({ "/one", "/two", "/claude/projects/-one" }) do
      vim.fn.mkdir(dir .. p, "p")
    end
    file = dir .. "/state/workspaces.json"
    projects = dir .. "/claude/projects"
    sessions = {}
    real_fishmonger = package.loaded["fishmonger"]
    package.loaded["fishmonger"] = {
      tabs = function(tab)
        local id = sessions[tab]
        return id and { { slot = 1, agent = { session = id } } } or {}
      end,
    }
    state.setup({ file = file, claude_projects = projects })
  end)

  after_each(function()
    vim.cmd("tabfirst | silent! tabonly")
    vim.wait(20)
    pcall(vim.api.nvim_del_augroup_by_name, "workspace_state")
    package.loaded["fishmonger"] = real_fishmonger
    local workspace = require("config.workspace")
    workspace.open = real_workspace_open or workspace.open
    vim.fn.delete(dir, "rf")
  end)

  it("saves each workspace's directory, number and terminal 1's session", function()
    sessions[workspace_tab(dir .. "/one", 1)] = A
    workspace_tab(dir .. "/two", 2)
    state.save()
    assert.same(
      { [dir .. "/one"] = { slot = 1, session = A }, [dir .. "/two"] = { slot = 2 } },
      stored()
    )
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
    state.save()
    sessions[tab] = nil
    state.save()
    assert.same({ [dir .. "/one"] = { slot = 1, session = A } }, stored())
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
      vim.fn.mkdir(vim.fs.dirname(file), "p")
      vim.fn.writefile({
        vim.json.encode({
          [dir .. "/one"] = { slot = 1, session = A },
          [dir .. "/two"] = { slot = 2, session = B },
          [dir .. "/gone"] = { slot = 3, session = A },
        }),
      }, file)
      vim.fn.writefile({}, projects .. "/-one/" .. A .. ".jsonl")
    end)

    it("resumes a session with a transcript and leaves one without to --continue", function()
      state.restore()
      assert.same({
        { dir = dir .. "/one", slot = 1, resume = A },
        { dir = dir .. "/two", slot = 2 },
      }, opened)
      local workspace = require("config.workspace")
      assert.equals("claude --resume " .. A, workspace.agent_shell(false, nil, opened[1].resume)[5])
      assert.equals(
        "claude --continue; or claude",
        workspace.agent_shell(false, nil, opened[2].resume)[5]
      )
    end)

    it("drops a project whose directory is gone from the file", function()
      state.restore()
      assert.is_nil(stored()[dir .. "/gone"])
      assert.is_not_nil(stored()[dir .. "/two"])
    end)
  end)
end)
