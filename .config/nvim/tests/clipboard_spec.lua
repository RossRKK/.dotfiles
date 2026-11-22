local assert = require("luassert")
local clipboard = require("util.clipboard")

-- A Vim register cannot hold a NUL: the register representation rewrites each
-- one to NL. Anything arriving from getreg has already been through that, so
-- specs must assert on the transformed bytes -- testing a pristine file header
-- would pass checks that the real thing defeats.
local function as_register(s)
  return (s:gsub("%z", "\n"))
end

describe("clipboard.is_text", function()
  it("accepts ordinary text", function()
    assert.is_true(clipboard.is_text("hello world"))
    assert.is_true(clipboard.is_text("multi\nline\ttext\r\n"))
    assert.is_true(clipboard.is_text("émoji ✨ utf-8"))
  end)

  it("accepts copied terminal output carrying ANSI escapes", function()
    assert.is_true(clipboard.is_text("\27[31mred\27[0m"))
  end)

  it("rejects nothing to paste", function()
    assert.is_false(clipboard.is_text(""))
    assert.is_false(clipboard.is_text(nil))
  end)

  -- The bug this guards: bare `wl-paste` dumps raw image bytes when the source
  -- offers no text/plain, so getreg succeeds and the image would be shoved into
  -- the pty as if it were text.
  it("rejects images as a register delivers them", function()
    assert.is_false(clipboard.is_text(as_register("\137PNG\r\n\26\n\0\0\0\13IHDR")))
    assert.is_false(clipboard.is_text(as_register("\255\216\255\224\0\16JFIF")))
    assert.is_false(clipboard.is_text(as_register("GIF89a\1\0")))
    assert.is_false(clipboard.is_text(as_register("BM\54\0\0\0")))
    assert.is_false(clipboard.is_text(as_register("RIFF\0\0\0\0WEBP")))
  end)

  -- Regression: a NUL scan passes this, because there is no NUL left to find.
  it("rejects a PNG header with every NUL already rewritten to NL", function()
    local png = "\137PNG\r\n\26\n\n\n\n\rIHDR"
    assert.is_nil(png:find("%z"))
    assert.is_false(clipboard.is_text(png))
  end)

  it("rejects binary with no known magic", function()
    assert.is_false(clipboard.is_text(as_register("\1\2\3\0\4")))
  end)

  it("only sniffs the head, so a long text paste stays text", function()
    assert.is_true(clipboard.is_text(string.rep("a", 100000)))
  end)
end)

describe("clipboard.text", function()
  local getreg = vim.fn.getreg

  after_each(function()
    vim.fn.getreg = getreg
  end)

  --- The `+` register as a provider gives it: `contents`, or the provider's error.
  local function register(contents, err)
    vim.fn.getreg = function(regname, list, ...) ---@diagnostic disable-line: duplicate-set-field, unused-local
      if err then
        error(err)
      end
      return contents
    end
  end

  it("is the clipboard's text", function()
    register("hello")
    assert.equals("hello", clipboard.text())
  end)

  -- Neovide's provider fails outright on an image.
  it("is nil, without raising, when the provider fails on an image", function()
    register(nil, "cannot get clipboard contents")
    assert.is_nil(clipboard.text())
  end)

  it("is nil when the provider hands over an image's bytes", function()
    register(as_register("\137PNG\r\n\26\n\0\0\0\13IHDR"))
    assert.is_nil(clipboard.text())
  end)
end)

describe("clipboard.parse_script_output", function()
  it("reads an image as its PNG bytes", function()
    local png = "\137PNG\r\n\26\n\0\0\0\13IHDR"
    assert.same({ kind = "image", png = png }, clipboard.parse_script_output("png " .. vim.base64.encode(png) .. "\r\n"))
  end)

  it("reads files copied in Explorer as their Windows paths", function()
    assert.same(
      { kind = "files", paths = { [[C:\Users\me\Shot 1.png]], [[D:\x.txt]] } },
      clipboard.parse_script_output("file C:\\Users\\me\\Shot 1.png\r\nfile D:\\x.txt\r\n")
    )
  end)

  it("reads files copied in Finder as their paths", function()
    assert.same(
      { kind = "files", paths = { "/Users/me/Shot 1.png", "/tmp/x.txt" } },
      clipboard.parse_script_output("file /Users/me/Shot 1.png\nfile /tmp/x.txt\n")
    )
  end)

  it("is nil for neither", function()
    assert.is_nil(clipboard.parse_script_output(""))
    assert.is_nil(clipboard.parse_script_output("\n"))
  end)
end)

describe("clipboard.read", function()
  local has, notify, display = vim.fn.has, vim.notify, vim.env.WAYLAND_DISPLAY
  local readers = { clipboard.read_windows, clipboard.read_mac, clipboard.read_wayland }

  after_each(function()
    vim.fn.has, vim.notify, vim.env.WAYLAND_DISPLAY = has, notify, display
    clipboard.read_windows, clipboard.read_mac, clipboard.read_wayland = unpack(readers)
  end)

  --- Which clipboard `read` reads with these `features` (`has` true) and `$WAYLAND_DISPLAY`, and what it notified.
  local function reads_from(features, wayland_display)
    local from, notified
    vim.fn.has = function(feature, ...) ---@diagnostic disable-line: duplicate-set-field, unused-local
      return vim.tbl_contains(features, feature) and 1 or 0
    end
    vim.env.WAYLAND_DISPLAY = wayland_display
    vim.notify = function(msg, level, opts) ---@diagnostic disable-line: duplicate-set-field, unused-local
      notified = level
    end
    for _, source in ipairs({ "windows", "mac", "wayland" }) do
      clipboard["read_" .. source] = function()
        from = source
      end
    end
    clipboard.read(function() end)
    return from, notified
  end

  -- The bug this guards: spawning a reader the platform lacks (powershell.exe, wl-paste) raised ENOENT.
  for _, case in ipairs({
    { "Windows' on WSL, even under WSLg's Wayland", { "wsl", "unix" }, "wayland-0", "windows" },
    { "the macOS pasteboard on a Mac", { "mac", "unix" }, nil, "mac" },
    { "Wayland's under Wayland", { "unix" }, "wayland-1", "wayland" },
  }) do
    local name, features, wayland_display, source = unpack(case)
    it("reads " .. name, function()
      assert.same({ source }, { reads_from(features, wayland_display) })
    end)
  end

  it("says so, spawning nothing, where it has no reader (X11)", function()
    assert.same({ nil, vim.log.levels.WARN }, { reads_from({ "unix" }, "") })
    assert.same({ nil, vim.log.levels.WARN }, { reads_from({ "unix" }, nil) })
  end)
end)

describe("clipboard.wayland_type", function()
  it("reads a PNG when one is offered, whatever else is", function()
    assert.equals("image/png", clipboard.wayland_type("application/x-qt-image\nimage/png\nimage/bmp\n"))
  end)

  it("reads copied files' URIs when there is no PNG", function()
    assert.equals("text/uri-list", clipboard.wayland_type("text/uri-list\ntext/plain\n"))
  end)

  it("reads nothing for neither", function()
    assert.is_nil(clipboard.wayland_type("text/plain\n"))
    assert.is_nil(clipboard.wayland_type(""))
  end)
end)

describe("clipboard.parse_wayland", function()
  it("reads an image as its PNG bytes", function()
    local png = "\137PNG\r\n\26\n\0\0\0\13IHDR"
    assert.same({ kind = "image", png = png }, clipboard.parse_wayland("image/png", png))
  end)

  it("reads copied files as their paths, skipping comments and other schemes", function()
    assert.same(
      { kind = "files", paths = { "/home/me/Shot 1.png", "/tmp/x.txt" } },
      clipboard.parse_wayland(
        "text/uri-list",
        "# copied\r\nfile:///home/me/Shot%201.png\r\nhttps://example.com/y\r\nfile:///tmp/x.txt\r\n"
      )
    )
  end)

  it("is nil for an empty image or no local file", function()
    assert.is_nil(clipboard.parse_wayland("image/png", ""))
    assert.is_nil(clipboard.parse_wayland("text/uri-list", "https://example.com/y\n"))
  end)
end)

describe("clipboard.path_in", function()
  it("is a Linux path", function()
    assert.equals("/tmp/shot.png", clipboard.path_in("/tmp/shot.png\n"))
  end)

  it("is not text with more than a path", function()
    assert.is_nil(clipboard.path_in("see /tmp/shot.png"))
    assert.is_nil(clipboard.path_in("/tmp/a.png\n/tmp/b.png"))
  end)

  -- The real wslpath: a stub would test the stub.
  it("is a quoted Windows path, as Explorer's Copy as path gives it, as WSL sees it", function()
    if vim.fn.executable("wslpath") == 0 then
      return pending("needs WSL")
    end
    local file = vim.fn.tempname()
    vim.fn.writefile({}, file)
    local windows = vim.trim(vim.system({ "wslpath", "-w", file }, { text = true }):wait().stdout)

    assert.equals(file, clipboard.path_in('"' .. windows .. '"'))
  end)
end)

describe("clipboard.neovide_provider", function()
  local requests

  --- A provider over Neovide's RPC, its clipboard read failing with `err` or holding `lines`.
  local function provider(lines, err)
    requests = {}
    return clipboard.neovide_provider(function(method, ...)
      requests[#requests + 1] = { method, ... }
      if err then
        error(err)
      end
      return lines
    end)
  end

  it("reads the clipboard through Neovide", function()
    assert.same({ "hi" }, provider({ "hi" }).paste["+"]())
    assert.same({ { "neovide.get_clipboard", "+" } }, requests)
  end)

  -- Empty, so a put says E353 rather than dumping Neovide's error.
  it("reads a clipboard Neovide can't (an image) as empty", function()
    assert.same({}, provider(nil, "cannot get clipboard contents").paste["*"]())
  end)

  it("copies through Neovide", function()
    provider().copy["+"]({ "a", "b" }, "v")
    assert.same({ { "neovide.set_clipboard", { "a", "b" }, "+" } }, requests)
  end)
end)
