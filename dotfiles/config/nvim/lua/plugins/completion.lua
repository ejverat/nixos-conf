-- One completion engine: blink.cmp. Its Rust fuzzy matcher lives in
-- blink.cmp/target/release and cargo is available through the Nix wrapper.
-- Snippets come from friendly-snippets through blink's own snippets source
-- (LuaSnip is not installed any more).
return {
  {
    "saghen/blink.cmp",
    event = { "InsertEnter", "CmdlineEnter" },
    version = false,
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
