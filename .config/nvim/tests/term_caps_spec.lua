-- Inline-image capability detection in config/term_caps.lua. Worth pinning
-- because two unrelated places branch on it at load time (image.nvim's `cond`
-- and open-external's extension list), and the Ghostty signals it reads are
-- inherited env vars -- easy to regress into a false positive under a GUI.

local assert = require("luassert")
local caps = require("config.term_caps")

describe("term_caps.inline_images_supported", function()
  local env, neovide

  before_each(function()
    env = { TERM_PROGRAM = vim.env.TERM_PROGRAM, GHOSTTY_RESOURCES_DIR = vim.env.GHOSTTY_RESOURCES_DIR }
    neovide = vim.g.neovide
    vim.env.TERM_PROGRAM = nil
    vim.env.GHOSTTY_RESOURCES_DIR = nil
    vim.g.neovide = nil
  end)

  after_each(function()
    vim.env.TERM_PROGRAM = env.TERM_PROGRAM
    vim.env.GHOSTTY_RESOURCES_DIR = env.GHOSTTY_RESOURCES_DIR
    vim.g.neovide = neovide
  end)

  it("is true under Ghostty, by either signal", function()
    vim.env.TERM_PROGRAM = "ghostty"
    assert.is_true(caps.inline_images_supported())

    vim.env.TERM_PROGRAM = "tmux" -- masked inside a multiplexer
    vim.env.GHOSTTY_RESOURCES_DIR = "/usr/share/ghostty"
    assert.is_true(caps.inline_images_supported())
  end)

  it("is false in other terminals", function()
    vim.env.TERM_PROGRAM = "WezTerm"
    assert.is_false(caps.inline_images_supported())
  end)

  -- The regression this guards: `neovide` launched from a Ghostty shell inherits
  -- Ghostty's env, but draws its own grid and speaks no graphics protocol.
  it("is false under Neovide even with Ghostty's env inherited", function()
    vim.env.TERM_PROGRAM = "ghostty"
    vim.env.GHOSTTY_RESOURCES_DIR = "/usr/share/ghostty"
    vim.g.neovide = true
    assert.is_false(caps.inline_images_supported())
  end)
end)
