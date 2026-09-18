-- Interactive Jupyter kernel execution (Python notebooks / cells) from Neovim.
--
-- Requirements (already handled elsewhere):
--   * Neovim's python3 remote-plugin host must have `pynvim` + `jupyter_client`
--     (configured in ~/nixos-conf/modules/features/neovim.nix).
--   * The actual kernel (numpy/numba/scipy/matplotlib/ipykernel) comes from the
--     project's `nix develop` shell, so launch nvim from inside it.
return {
  {
    "benlubas/molten-nvim",
    -- molten is a remote plugin: it must be on the runtimepath at startup so
    -- `:UpdateRemotePlugins` (see `build`) can register its python3 host.
    lazy = false,
    build = ":UpdateRemotePlugins",
    init = function()
      -- WezTerm no renderiza el kitty graphics protocol (falla con y sin tmux),
      -- así que image.nvim usa el backend `ueberzug` (ueberzugpp) para el
      -- output inline de matplotlib.
      vim.g.molten_image_provider = "image.nvim"
      vim.g.molten_output_win_max_height = 20
      vim.g.molten_auto_open_output = true
      -- Alternativa: salida persistente como virtual text (se queda pegada
      -- debajo de la celda aunque saques el cursor). Descomentá si la preferís:
      -- vim.g.molten_virt_text_output = true
    end,
    keys = {
      { "<leader>mi", ":MoltenInit python3<CR>", desc = "Molten: init kernel (python3)" },
      { "<leader>me", ":MoltenEvaluateOperator<CR>", mode = "n", desc = "Molten: evaluate (operator + motion)" },
      { "<leader>ml", ":MoltenEvaluateLine<CR>", desc = "Molten: evaluate line" },
      { "<leader>mv", ":<C-u>MoltenEvaluateVisual<CR>gv", mode = "v", desc = "Molten: evaluate selection" },
      { "<leader>mr", ":MoltenReevaluateCell<CR>", desc = "Molten: re-evaluate cell" },
      { "<leader>mo", ":MoltenShowOutput<CR>", desc = "Molten: show output" },
      { "<leader>mO", ":noautocmd MoltenEnterOutput<CR>", desc = "Molten: open/enter output window" },
      { "<leader>md", ":MoltenHideOutput<CR>", desc = "Molten: hide output" },
      { "<leader>mj", ":MoltenNext<CR>", desc = "Molten: next cell" },
      { "<leader>mk", ":MoltenPrev<CR>", desc = "Molten: previous cell" },
      { "<leader>mx", ":MoltenInterrupt<CR>", desc = "Molten: interrupt" },
      { "<leader>mR", ":MoltenRestart<CR>", desc = "Molten: restart kernel" },
    },
  },

  -- Image rendering backend for molten output (matplotlib figures, etc.).
  {
    "3rd/image.nvim",
    lazy = false,
    build = false,
    opts = {
      -- WezTerm no renderiza el kitty graphics protocol (testeado: falla con y
      -- sin tmux). `ueberzug` usa ueberzugpp (overlay externo) y funciona con
      -- cualquier terminal. Requiere pkgs.ueberzugpp en neovimExtraPkgs.
      backend = "ueberzug",
    },
  },
}
