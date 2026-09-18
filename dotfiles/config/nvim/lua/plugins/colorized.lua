return {
  {
    "catgoose/nvim-colorizer.lua",
    event = "BufReadPre",
    opts = { -- set to setup table
      mode = "virtualtext",
      css = true,
    },
  },
  {
    "max397574/colortils.nvim",
    opts = {
      cmd = "Colortils",
    },
  },
}
