-- `jj log` for the greeter: run it coloured, turn the ANSI output into snacks
-- text chunks, and cut every line to the dashboard's width without disturbing
-- the graph column.
--
-- The graph is a block, not a list of lines: the rails in column 0..N of one
-- line continue into the next, so every line has to keep the same left edge.
-- That rules out snacks' per-line centring -- the chunks here carry no `align`,
-- and rely on the dashboard pane itself being centred in the window.
--
-- Colour comes from jj's own SGR codes rather than a template, so the greeter
-- shows the same marks as the terminal (the green @, the purple change id, the
-- bookmark names) and follows the user's jj colour config. Each 256-colour index
-- becomes a highlight group built from the terminal palette (vim.g.terminal_color_N),
-- which is what jjui in the side terminal paints with too.
--
-- The pure parts (parse, truncate) take strings and return tables so the test
-- suite can drive them without a jj repo or a dashboard.

local M = {}

-- Highlight groups made so far: "<colour index>" or "<colour index>b" (bold).
local groups = {}

--- The highlight group for a 256-colour index, created on first use. Bold gets
--- its own group so a bold @ stays bold. Colours 0-15 come from the terminal
--- palette so the graph matches the shell's jj; higher indexes fall back to
--- the standard xterm cube via ctermfg, which only shows in a 256-colour
--- terminal without termguicolors -- jj's defaults never go above 15.
---@param index integer
---@param bold boolean
---@return string
local function group(index, bold)
  local key = index .. (bold and "b" or "")
  if not groups[key] then
    local name = "GreeterAnsi" .. key
    local fg = vim.g["terminal_color_" .. index]
    vim.api.nvim_set_hl(0, name, { fg = fg, ctermfg = index, bold = bold or nil })
    groups[key] = name
  end
  return groups[key]
end

--- Apply one SGR parameter list to a colour state.
---@param params string the bytes between ESC[ and m, e.g. "1;38;5;2"
---@param state {fg: integer?, bold: boolean}
local function apply(params, state)
  local codes = {}
  for n in params:gmatch("%d+") do
    codes[#codes + 1] = tonumber(n)
  end
  if #codes == 0 then
    codes = { 0 }
  end
  local i = 1
  while i <= #codes do
    local c = codes[i]
    if c == 0 then
      state.fg, state.bold = nil, false
    elseif c == 1 then
      state.bold = true
    elseif c == 22 then
      state.bold = false
    elseif c == 39 then
      state.fg = nil
    elseif c >= 30 and c <= 37 then
      state.fg = c - 30
    elseif c >= 90 and c <= 97 then
      state.fg = c - 90 + 8
    elseif c == 38 and codes[i + 1] == 5 then
      state.fg = codes[i + 2]
      i = i + 2
    elseif c == 38 and codes[i + 1] == 2 then
      -- Truecolor: no palette slot to map it to, so leave the default.
      i = i + 4
    end
    i = i + 1
  end
end

--- One ANSI-coloured line as snacks text chunks. The `hl` of a chunk is the
--- highlight group name, or nil for default-coloured text. Returned chunks carry
--- `fg`/`bold` too, so a caller (or a test) can see the colour decision without
--- looking up the group.
---@param raw string
---@return table[] chunks
function M.parse(raw)
  local chunks = {}
  local state = { fg = nil, bold = false }
  local pos = 1
  local function emit(text)
    if text == "" then
      return
    end
    local last = chunks[#chunks]
    if last and last.fg == state.fg and last.bold == state.bold then
      last[1] = last[1] .. text
      return
    end
    chunks[#chunks + 1] = {
      text,
      hl = state.fg and group(state.fg, state.bold) or (state.bold and group(7, true) or nil),
      fg = state.fg,
      bold = state.bold,
    }
  end
  while pos <= #raw do
    local s, e, params = raw:find("\27%[([%d;]*)m", pos)
    if not s then
      emit(raw:sub(pos))
      break
    end
    emit(raw:sub(pos, s - 1))
    apply(params, state)
    pos = e + 1
  end
  return chunks
end

--- Cut a chunk list to `width` display columns. Multibyte-safe: the graph is
--- box-drawing glyphs, and a byte-wise cut would split one. A cut line ends in
--- an ellipsis, which takes one of the columns.
---@param chunks table[]
---@param width integer
---@return table[]
function M.truncate(chunks, width)
  local total = 0
  for _, c in ipairs(chunks) do
    total = total + vim.fn.strdisplaywidth(c[1])
  end
  if total <= width then
    return chunks
  end
  local out, used = {}, 0
  local budget = width - 1 -- room for the ellipsis
  for _, c in ipairs(chunks) do
    local w = vim.fn.strdisplaywidth(c[1])
    if used + w <= budget then
      out[#out + 1] = c
      used = used + w
    else
      -- Take as many whole characters as fit.
      local kept = ""
      for ch in c[1]:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local cw = vim.fn.strdisplaywidth(ch)
        if used + cw > budget then
          break
        end
        kept = kept .. ch
        used = used + cw
      end
      if kept ~= "" then
        out[#out + 1] = vim.tbl_extend("force", {}, c, { kept })
      end
      break
    end
  end
  out[#out + 1] = { "\xe2\x80\xa6", hl = "SnacksDashboardDesc" }
  return out
end

--- Whole `jj log` output as dashboard items, one per line, each cut to `width`.
---@param output string
---@param width integer
---@return table[] items
function M.items(output, width)
  local items = {}
  for _, raw in ipairs(vim.split(output, "\n", { plain = true })) do
    if raw ~= "" then
      items[#items + 1] = { text = M.truncate(M.parse(raw), width) }
    end
  end
  return items
end

-- Last output per root, so the greeter can draw before a fresh run finishes and
-- redraw only when the log actually changed.
M.cache = {}
local running = {}

--- Run `jj log` for `root`, coloured, at most `lines` lines of output, and hand
--- the raw text to `on_change` if it differs from the cached one. One run per
--- root at a time: a burst of watcher events must not stack jj processes.
---
--- --ignore-working-copy keeps the greeter from snapshotting the working copy on
--- every redraw. The cost is that `@` reads (empty) until some other jj command
--- snapshots; the op_heads watcher then repaints from that command's result.
---@param root string
---@param lines integer
---@param on_change fun(output: string)
function M.fetch(root, lines, on_change)
  if running[root] or vim.fn.executable("jj") == 0 then
    return
  end
  running[root] = true
  vim.system({
    "jj",
    "--color=always",
    "--no-pager",
    "--ignore-working-copy",
    "log",
    "-n",
    tostring(lines),
  }, { cwd = root, text = true }, function(out)
    running[root] = nil
    if out.code ~= 0 then
      return
    end
    local output = out.stdout or ""
    if M.cache[root] ~= output then
      M.cache[root] = output
      vim.schedule(function()
        on_change(output)
      end)
    end
  end)
end

return M
