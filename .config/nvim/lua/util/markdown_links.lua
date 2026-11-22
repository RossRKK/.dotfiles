-- File and anchor links are left to marksman; only URLs need opening outside nvim.
local M = {}

-- Declared ahead so the helpers can follow the code that uses them.
local destination, definition, normalize, child, unwrap

local link_types = {
  inline_link = true,
  image = true,
  uri_autolink = true,
  full_reference_link = true,
  collapsed_reference_link = true,
  shortcut_link = true,
}

--- The URL of the markdown link at `cursor` in `buf`, or nil when the cursor isn't
--- on a link or its destination has no URL scheme (a file, an anchor).
---@param buf integer
---@param cursor [integer, integer] (1-based row, 0-based byte column), as nvim_win_get_cursor
---@return string?
function M.url_at(buf, cursor)
  local parser = vim.treesitter.get_parser(buf, nil, { error = false })
  if not parser then
    return nil
  end
  local row, col = cursor[1] - 1, cursor[2]
  parser:parse({ row, row + 1 })
  local node =
    vim.treesitter.get_node({ bufnr = buf, pos = { row, col }, ignore_injections = false })
  while node and not link_types[node:type()] do
    node = node:parent()
  end
  local target = node and destination(buf, parser, node)
  return target and M.url(target)
end

--- `text` itself when it starts with a URL scheme (CommonMark's 2-32 characters), else nil.
---@param text string
---@return string?
function M.url(text)
  local scheme = text:match("^(%a[%w+.-]*):")
  return scheme and #scheme >= 2 and #scheme <= 32 and text or nil
end

--- A link node's destination, a reference link's taken from its definition.
---@param buf integer
---@param parser vim.treesitter.LanguageTree
---@param link TSNode
---@return string?
function destination(buf, parser, link)
  local kind = link:type()
  if kind == "uri_autolink" then
    return unwrap(vim.treesitter.get_node_text(link, buf))
  end
  if kind == "inline_link" or kind == "image" then
    local target = child(link, "link_destination")
    return target and unwrap(vim.treesitter.get_node_text(target, buf))
  end
  local label = child(link, "link_label") or child(link, "link_text")
  return label and definition(buf, parser, vim.treesitter.get_node_text(label, buf))
end

--- The destination of the `[label]: destination` definition matching `label`, if any.
---@param buf integer
---@param parser vim.treesitter.LanguageTree
---@param label string
---@return string?
function definition(buf, parser, label)
  local query = vim.treesitter.query.parse(
    "markdown",
    "(link_reference_definition (link_label) @label (link_destination) @destination)"
  )
  local wanted = normalize(label)
  for _, match in query:iter_matches(parser:parse()[1]:root(), buf) do
    if normalize(vim.treesitter.get_node_text(match[1][1], buf)) == wanted then
      return unwrap(vim.treesitter.get_node_text(match[2][1], buf))
    end
  end
end

-- Labels match case-insensitively with runs of whitespace collapsed, per CommonMark.
---@param label string
---@return string
function normalize(label)
  return vim.trim(label:gsub("^%[", ""):gsub("%]$", "")):gsub("%s+", " "):lower()
end

---@param node TSNode
---@param kind string
---@return TSNode?
function child(node, kind)
  for found in node:iter_children() do
    if found:type() == kind then
      return found
    end
  end
end

-- Autolinks and `<...>` destinations keep their angle brackets in the tree.
---@param text string
---@return string
function unwrap(text)
  return (text:gsub("^<(.*)>$", "%1"))
end

return M
