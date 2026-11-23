local assert = require("luassert")
local plugin_dirs = require("config.plugin_dirs")

describe("plugin_dirs.parse_dev", function()
  it("reads nothing from an unset or empty variable", function()
    assert.same({}, plugin_dirs.parse_dev(nil, "/home/me/dev"))
    assert.same({}, plugin_dirs.parse_dev("", "/home/me/dev"))
  end)

  it("puts a bare name's checkout under the dev root", function()
    assert.same(
      { ["fishmonger.nvim"] = "/home/me/dev/fishmonger.nvim", ["agentic.nvim"] = "/home/me/dev/agentic.nvim" },
      plugin_dirs.parse_dev("fishmonger.nvim,agentic.nvim", "/home/me/dev")
    )
  end)

  it("takes name=dir for a checkout elsewhere, such as a worktree", function()
    assert.same(
      { ["triage.nvim"] = "/tmp/wt/triage" },
      plugin_dirs.parse_dev(" triage.nvim=/tmp/wt/triage ", "/home/me/dev")
    )
  end)
end)

describe("plugin_dirs.resolver", function()
  local root
  before_each(function()
    root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/dev/fishmonger.nvim", "p")
  end)
  after_each(function()
    vim.fn.delete(root, "rf")
  end)

  local nix = { ["fishmonger.nvim"] = "/nix/store/x-fishmonger", ["snacks.nvim"] = "/nix/store/y-snacks" }

  it("loads a plugin from its nix build", function()
    local dir = plugin_dirs.resolver(nix, {})
    assert.equals("/nix/store/y-snacks", dir({ name = "snacks.nvim" }))
  end)

  it("loads a plugin named for development from its checkout", function()
    local dir = plugin_dirs.resolver(nix, { ["fishmonger.nvim"] = root .. "/dev/fishmonger.nvim" })
    assert.equals(root .. "/dev/fishmonger.nvim", dir({ name = "fishmonger.nvim" }))
    assert.equals("/nix/store/y-snacks", dir({ name = "snacks.nvim" }))
  end)

  it("refuses a development checkout that isn't there rather than loading the pinned build", function()
    local dir = plugin_dirs.resolver(nix, { ["snacks.nvim"] = root .. "/dev/snacks.nvim" })
    assert.has_error(function()
      dir({ name = "snacks.nvim" })
    end, "NVIM_DEV_PLUGINS: no checkout of snacks.nvim at " .. root .. "/dev/snacks.nvim")
  end)

  it("refuses a plugin the nix build doesn't carry", function()
    local dir = plugin_dirs.resolver(nix, {})
    assert.has_error(function()
      dir({ name = "missing.nvim" })
    end, "missing.nvim isn't in the nix build: add it to nvim-package.nix")
  end)

  it("refuses a development checkout of a plugin the build doesn't carry, such as a misspelt name", function()
    assert.has_error(function()
      plugin_dirs.resolver(nix, { ["fishmonger"] = root .. "/dev/fishmonger.nvim" })
    end, "NVIM_DEV_PLUGINS: fishmonger isn't a plugin in the nix build")
  end)
end)
