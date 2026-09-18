return {
  {
    "taku25/UnrealDev.nvim",
    -- Load when opening C/C++ files or on demand with :UDEV
    ft = { "cpp", "c" },
    cmd = "UDEV",
    dependencies = {
      -- Core shared library (required). Its Rust scanner is built by the
      -- `build` hook below, so cargo/rustc must be available in nvim's PATH
      -- (provided via the NixOS neovim wrapper extraPackages).
      {
        "taku25/UNL.nvim",
        lazy = false,
        build = "cargo build --release --manifest-path scanner/Cargo.toml",
      },
      "taku25/UEP.nvim", -- project explorer
      "taku25/UEA.nvim", -- asset (Blueprint) inspector
      "taku25/UBT.nvim", -- build tool
      "taku25/UCM.nvim", -- class manager
      "taku25/ULG.nvim", -- log viewer
      "taku25/USH.nvim", -- Unreal shell
      {
        "taku25/UNX.nvim", -- logical view / explorer
        dependencies = {
          "MunifTanjim/nui.nvim",
          "nvim-tree/nvim-web-devicons",
        },
      },
      "taku25/UDB.nvim", -- debug (nvim-dap)
      {
        "taku25/USX.nvim", -- filetype detection + Unreal syntax queries
        lazy = false,
        opts = {},
      },
    },
    opts = {
      -- Enable setup() for every installed suite plugin.
      setup_modules = {
        UBT = true,
        UEP = true,
        ULG = true,
        USH = true,
        UCM = true,
        UEA = true,
        UNX = true,
        UDB = true,
      },
      -- Source-built engine (bot-arena has no EngineAssociation, so UBT cannot
      -- auto-detect it). Point it at your UE clone.
      engine_path = "/home/ejverat/Projects/UnrealGames/UnrealEngine",
      -- The defaults ship with Win64 presets; override with Linux ones.
      presets = {
        { name = "LinuxDevelopment", Platform = "Linux", IsEditor = false, Configuration = "Development" },
        { name = "LinuxDevelopmentEditor", Platform = "Linux", IsEditor = true, Configuration = "Development" },
        { name = "LinuxDebugGame", Platform = "Linux", IsEditor = false, Configuration = "DebugGame" },
        { name = "LinuxDebugGameEditor", Platform = "Linux", IsEditor = true, Configuration = "DebugGame" },
        { name = "LinuxShipping", Platform = "Linux", IsEditor = false, Configuration = "Shipping" },
      },
      preset_target = "LinuxDevelopmentEditor",
    },
    keys = {
      { "<leader>uef", function() require("UnrealDev.api").files({}) end, desc = "Unreal: Find project files" },
      { "<leader>ueg", function() require("UnrealDev.api").grep({}) end, desc = "Unreal: Grep project" },
      {
        "<leader>ues",
        function()
          require("UnrealDev.api").switch_file({ current_file_path = vim.api.nvim_buf_get_name(0) })
        end,
        desc = "Unreal: Switch header/source",
      },
      { "<leader>uec", function() require("UnrealDev.api").classes({}) end, desc = "Unreal: Find class" },
      { "<leader>ueb", function() require("UnrealDev.api").build({}) end, desc = "Unreal: Build target" },
      { "<leader>uer", function() require("UnrealDev.api").refresh({}) end, desc = "Unreal: Refresh project DB" },
    },
  },
  {
    -- Manages the tree-sitter parsers needed for Unreal development.
    -- It installs the Unreal-patched cpp parser (taku25/tree-sitter-cpp) plus
    -- the custom ushader/verse grammars. Requires `tree-sitter` CLI (already in
    -- the nvim wrapper extraPackages) and a C compiler (gcc).
    "romus204/tree-sitter-manager.nvim",
    opts = {
      ensure_installed = { "cpp", "ushader", "verse" },
      highlight = { "cpp", "ushader", "verse" },
      languages = {
        cpp = {
          install_info = {
            url = "https://github.com/taku25/tree-sitter-cpp",
            use_repo_queries = true,
          },
        },
        ushader = {
          install_info = {
            url = "https://github.com/taku25/tree-sitter-unreal-shader",
            use_repo_queries = true,
          },
        },
        verse = {
          install_info = {
            url = "https://github.com/taku25/tree-sitter-verse",
            use_repo_queries = true,
          },
        },
      },
    },
    config = function(_, opts)
      vim.filetype.add({
        extension = {
          verse = "verse",
          usf = "ushader",
          ush = "ushader",
        },
      })
      require("tree-sitter-manager").setup(opts)
    end,
  },
}
