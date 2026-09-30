-- Inline image rendering, for two unrelated consumers that share one backend:
--
--   * molten's matplotlib output in `python` buffers, and
--   * the raw-HTML `<img>` tags in Markdown, which is how `nbconvert` copies a
--     notebook cell into the `*.ipynb.md` views that `~/Projects/Courses/CUDA`
--     renders with its `nb2md` helper.
--
-- `image.nvim`'s stock `markdown` integration only matches `![alt](path)`, so
-- `lua/image/integrations/nb_html_images.lua` adds the HTML-tag case next to it.
--
-- Every value below was measured; odd/tasks/nvim-inline-notebook-images.md has
-- the evidence. The short version of the two non-obvious ones:
--
--   * `ueberzug` is not an option on this machine: image.nvim drives ueberzugpp
--     with `layer`, ueberzugpp links only xdg_shell (no zwlr_layer_shell), and a
--     Wayland client cannot place itself at absolute coordinates, so it opens
--     its own top-level window.
--   * inside tmux the images are erased again by nvim's own redraw, which
--     writes the blank cells the image occupies. Hence `repaint()` below.

local tmux = vim.env.TMUX ~= nil

-- Filetypes this spec is loaded for, used to skip the repaint work everywhere
-- else: `repaint()` ends up emitting a delete-all sequence even when the buffer
-- holds no images.
local image_filetypes = {
  markdown = true,
  markdown_inline = true,
  vimwiki = true,
  quarto = true,
  rmd = true,
  python = true,
}

-- Re-emit every rendered image.
--
-- Why it is needed: image.nvim only paints when it decides something changed, so
-- a painted image that the terminal later erased stays erased. `disable()` marks
-- each image as not rendered (and clears it), `enable()` renders them again.
-- Measured with `backend = "sixel"` on lab.ipynb.md, counting the DCS sequences
-- Neovim writes to the terminal: 3 at startup and 6 after this, so it really
-- re-emits. (A synthetic `WinScrolled` does not: 3, and firing `BufEnter` cannot
-- be used from a `BufEnter` listener.)
local function repaint()
  local image = require("image")
  if not image.is_enabled() then return end
  if #image.get_images() == 0 then return end
  image.disable()
  image.enable()
end

return {
  {
    "3rd/image.nvim",
    -- Same deferral as before, widened to the Markdown family: nothing else
    -- needs it, and it used to cost ~7 ms on every start.
    ft = { "python", "markdown", "vimwiki", "quarto", "rmd" },
    build = false,
    opts = {
      -- Two backends, decided by whether a multiplexer sits in between.
      --
      -- Outside tmux: `kitty`. WezTerm speaks it with its default config (DA1
      -- answers `?65;4;6;18;22;52c`, the kitty `a=q` query answers
      -- `ESC_Gi=1;OK`), it is the sharper of the two, and nothing rewrites the
      -- pane behind our back.
      --
      -- Inside tmux: `sixel`. tmux reports `sixel` in
      -- `#{client_termfeatures}`, so it renders sixel natively into its own
      -- screen model instead of forwarding a blindly-wrapped escape; kitty
      -- placements travel as absolute screen coordinates wrapped in DCS
      -- passthrough, and every pane redraw desyncs them from the text. Measured
      -- in tmux: kitty appears/disappears and shows in pieces, sixel stays put.
      -- Sixel also drops image.nvim's crop path (`features.crop = false`), which
      -- is what produced the pieces.
      --
      -- `unicode-placeholders` is not an option either: WezTerm does not
      -- implement the Unicode placeholder feature and paints the U+10EEEE cells
      -- as literal text, filling the screen with glyphs.
      backend = tmux and "sixel" or "kitty",
      -- Floating windows (which-key, dialogs) paint their own background over
      -- an image, and without this the image keeps showing through it and the
      -- text becomes unreadable. With it, lua/image/init.lua clears the images
      -- of any window a mask overlaps and restores them when it closes.
      window_overlap_clear_enabled = true,
      -- Registered next to the stock `markdown` integration, not instead of it:
      -- the two match disjoint node types (`image` vs `html_block`/`html_tag`),
      -- so nothing renders twice and the upstream Markdown query stays upstream.
      integrations = {
        nb_html_images = { enabled = true },
      },
    },
    -- `opts` alone is not enough here because the repaint below has to run after
    -- setup; lazy.nvim only calls setup itself when there is no `config`.
    config = function(_, opts)
      require("image").setup(opts)

      local uv = vim.uv or vim.loop
      local timer = nil

      local function schedule(delay)
        if not timer then timer = uv.new_timer() end
        timer:stop()
        timer:start(delay, 0, vim.schedule_wrap(repaint))
      end

      local group = vim.api.nvim_create_augroup("config_image_repaint", { clear = true })
      local function relevant(buffer)
        return image_filetypes[vim.bo[buffer].filetype] == true
      end

      if tmux then
        -- Inside tmux the erase happens on cursor motion, so that is what has to
        -- be debounced: repainting on every single motion would re-send the
        -- images continuously.
        vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
          group = group,
          callback = function(args)
            if relevant(args.buf) then schedule(180) end
          end,
        })
      else
        -- No multiplexer rewriting the pane, so only the first paint comes out
        -- wrong: one repaint after the buffer is on screen is enough.
        vim.api.nvim_create_autocmd("BufWinEnter", {
          group = group,
          callback = function(args)
            if relevant(args.buf) then schedule(300) end
          end,
        })
      end
    end,
  },
}
