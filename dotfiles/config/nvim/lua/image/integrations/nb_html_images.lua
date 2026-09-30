-- image.nvim integration for images written as raw HTML in Markdown.
--
-- Why this exists: image.nvim ships two integrations and neither one covers a
-- Markdown file whose images are raw HTML tags.
--
--   * `markdown` matches `![alt](path)` only -- a tree-sitter `image` node. Its
--     query is `(image (link_destination) @url)`.
--   * `html` runs on the `html` filetype and parses the buffer with the `html`
--     grammar, so it cannot open a Markdown buffer at all.
--
-- `nbconvert` copies a notebook's cell content verbatim, so every image in the
-- `*.ipynb.md` views rendered by `nb2md` arrives as `<img src="...">`. In
-- ~/Projects/Courses/CUDA/NsightLab that is 60 of the 63 image references; the
-- remaining 3 are `![png](...)` and stay with the stock `markdown` integration.
--
-- The parser classifies those tags as `html_block` (block-level HTML, one node
-- per blank-line-separated block) or `html_tag` (inline HTML, in the
-- `markdown_inline` child trees), never as `image`.
--
-- This integration is deliberately additive: it is registered next to the stock
-- `markdown` integration instead of replacing it, so the upstream Markdown query
-- and its `vimwiki`/Quarto coverage are not reimplemented here. The two match
-- disjoint node types, so nothing is rendered twice.
--
-- It lives under the runtimepath's own `lua/image/integrations/` namespace
-- because image.nvim resolves an integration by module name alone
-- (`require("image/integrations/" .. name)`) and ships no registration API; the
-- plugin itself lives in the Nix store and cannot be patched. That also means
-- `image/utils/document` is an internal path we depend on -- see
-- odd/tasks/nvim-inline-notebook-images.md, "Coupling accepted".

local document = require("image/utils/document")

---Find every `<img>` tag in a piece of HTML node text.
---
---A single `html_block` can hold several images (the
---`<td><center><img .../></center></td>` rows in `ncu/step1.ipynb.md`), so the
---text is scanned tag by tag and every tag reports its own row.
---
---@param text string node text
---@param base_row integer 0-based row where the node starts
---@return { row: integer, url: string }[]
local function find_html_images(text, base_row)
  local found = {}
  local pos = 1

  while true do
    local tag_start = text:find("<img", pos, true)
    if not tag_start then break end

    local tag_end = text:find(">", tag_start, true) or #text
    local tag = text:sub(tag_start, tag_end)

    -- The notebooks use all three forms: src="a.png", src='a.png' and the bare
    -- src=images/a.jpg taken straight from the cell text.
    local url = tag:match("[Ss][Rr][Cc]%s*=%s*\"([^\"]*)\"")
      or tag:match("[Ss][Rr][Cc]%s*=%s*'([^']*)'")
      or tag:match("[Ss][Rr][Cc]%s*=%s*([^%s>]+)")

    if url and url ~= "" then
      -- Count the newlines before the tag so a multi-line block puts each image
      -- on its own row instead of stacking them all on the first one.
      local before = text:sub(1, tag_start - 1)
      local _, newlines = before:gsub("\n", "")
      table.insert(found, { row = base_row + newlines, url = url })
    end

    pos = tag_start + 4
  end

  return found
end

---Walk every tree of the Markdown parser and collect its raw-HTML images.
---
---`parser:for_each_tree` reaches both the `markdown` tree (`html_block`) and the
---`markdown_inline` child trees (`html_tag`), which is why the walk does not have
---to know where inline nodes live. No tree-sitter query is involved: matching
---`node:type()` cannot fail on a grammar that lacks a node type, which a
---`query.parse` call would.
---
---@param buf integer
---@param parser vim.treesitter.LanguageTree
---@return { node: any, range: { start_row: integer, start_col: integer, end_row: integer, end_col: integer }, url: string }[]
local function collect_html_images(buf, parser)
  local images = {}
  local seen = {}

  parser:for_each_tree(function(tree)
    local stack = { tree:root() }

    while #stack > 0 do
      local node = table.remove(stack)

      if node:type() == "html_block" or node:type() == "html_tag" then
        local node_row = node:range()
        local text = vim.treesitter.get_node_text(node, buf)

        for _, hit in ipairs(find_html_images(text, node_row)) do
          -- One `<img>` tag is one match, and a tag reachable from two nodes
          -- must not produce two overlays.
          local key = ("%d:%s"):format(hit.row, hit.url)
          if not seen[key] then
            seen[key] = true
            table.insert(images, {
              node = node,
              -- Column 0 on purpose: these are block-level elements, and the
              -- tag column would push every `<center><img ...>` screenshot
              -- right by its indent while the image is scaled against the whole
              -- window width (`max_width_window_percentage`), overflowing the
              -- window edge.
              range = { start_row = hit.row, start_col = 0, end_row = hit.row, end_col = 0 },
              url = hit.url,
            })
          end
        end
      else
        for child in node:iter_children() do
          if child:named() then table.insert(stack, child) end
        end
      end
    end
  end)

  return images
end

---@param buffer integer?
local query_buffer_images = function(buffer)
  local buf = buffer or vim.api.nvim_get_current_buf()

  local parser = vim.treesitter.get_parser(buf, "markdown")
  parser:parse(true)

  return collect_html_images(buf, parser)
end

---@type DocumentIntegrationConfig
local config = {
  name = "nb_html_images",
  -- Mirrors the stock `markdown` integration, with `only_render_image_at_cursor`
  -- left false: the point is reading a notebook, where every figure should be on
  -- screen at once.
  default_options = {
    clear_in_insert_mode = false,
    download_remote_images = true,
    only_render_image_at_cursor = false,
    only_render_image_at_cursor_mode = "popup",
    floating_windows = false,
    filetypes = { "markdown", "vimwiki", "quarto", "rmd" },
  },
  query_buffer_images = query_buffer_images,
}

---@type table
local integration = document.create_document_integration(config)

-- Exposed so the query can be asserted without a terminal: the table
-- `create_document_integration` returns only carries `setup`, and the render
-- path is unreachable from a headless run.
integration._query_buffer_images = query_buffer_images

return integration
