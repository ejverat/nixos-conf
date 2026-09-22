-- One completion engine: blink.cmp. Its Rust fuzzy matcher lives in
-- blink.cmp/target/release and cargo is available through the Nix wrapper.
-- Snippets come from friendly-snippets through blink's own snippets source
-- (LuaSnip is not installed any more).
return {
  {
    "saghen/blink.cmp",
    event = { "InsertEnter", "CmdlineEnter" },
    -- Track the v1 line, not `main`: upstream main is v2 dev, which requires
    -- Neovim 0.12+ AND the separate `saghen/blink.lib` package, and moved the
    -- Rust matcher from target/release to lib/. v1.10.2 (`78336bc`, branch `v1`)
    -- is the commit the tracked lazy-lock.json pins; a v1 tag keeps
    -- `:Lazy update` from dragging the engine into an unreleased major.
    version = "1.*",
    dependencies = { "rafamadriz/friendly-snippets" },
    -- The Rust fuzzy matcher lives in target/release, which is gitignored
    -- upstream, so a fresh clone needs this build (cargo is on the wrapper
    -- PATH). Without it blink falls back to the Lua matcher and warns.
    build = "cargo build --release",
    opts = {
      keymap = {
        preset = "default",
        -- <C-l>/<C-h> placeholder jumps live in lua/config/keymaps.lua: blink's
        -- own snippet_forward/backward commands only exist while this menu is
        -- open, and the native vim.snippet jumps work in both states.
        ["<C-y>"] = { "select_and_accept" },
      },
      appearance = { nerd_font_variant = "mono" },
      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 200 },
        menu = { draw = { treesitter = { "lsp" } } },
      },
      snippets = { preset = "default" },
      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
        per_filetype = { lua = { inherit_defaults = true, "lazydev" } },
        providers = {
          lazydev = {
            name = "LazyDev",
            module = "lazydev.integrations.blink",
            score_offset = 100,
          },
        },
      },
      cmdline = {
        enabled = true,
        keymap = { preset = "cmdline" },
      },
    },
    config = function(_, opts)
      require("blink.cmp").setup(opts)
    end,
  },
}
