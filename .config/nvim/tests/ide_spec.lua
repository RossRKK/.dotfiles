-- IDE-mode detection in config/ide.lua. Window geometry (edge sizing) moved to
-- edgy; see lua/plugins/edgy.lua.

local assert = require("luassert")
local ide = require("config.ide")

describe("ide.is_ide_mode", function()
  -- Captured once at module load from argv, so headless (no directory argument)
  -- is always text-editor mode. Pins the contract the terminal/explorer autocmds
  -- branch on.
  it("is false when nvim was not given a single directory", function()
    assert.is_false(ide.is_ide_mode())
  end)
end)
