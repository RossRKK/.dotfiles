local assert = require("luassert")

-- util.nix_build decides between the nix build and lazy.nvim's own installs at
-- startup, so it must read as absent, not merely loaded, outside the build.
describe("util.nix_build", function()
  local saved_name, saved_preload

  before_each(function()
    saved_name = vim.g.nix_info_plugin_name
    saved_preload = package.preload["fake-nix-info"]
    package.loaded["util.nix_build"] = nil
  end)

  after_each(function()
    vim.g.nix_info_plugin_name = saved_name
    package.preload["fake-nix-info"] = saved_preload
    package.loaded["fake-nix-info"] = nil
    package.loaded["util.nix_build"] = nil
  end)

  it("has no build info in an nvim that isn't the nix build", function()
    vim.g.nix_info_plugin_name = nil
    assert.is_nil(require("util.nix_build").info)
  end)

  it("has the wrapper's info plugin in the nix build", function()
    local info = { plugins = { start = {}, lazy = {} }, settings = { config_directory = "/nix/store/x-nvim" } }
    package.preload["fake-nix-info"] = function()
      return info
    end
    vim.g.nix_info_plugin_name = "fake-nix-info"
    assert.equals(info, require("util.nix_build").info)
  end)
end)
