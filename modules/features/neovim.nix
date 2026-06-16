{ self, inputs, ... }: {
  flake.nixosModules.neovim = { config, pkgs, lib, ... }: let
    myNeovim = self.packages.${pkgs.stdenv.hostPlatform.system}.myNeovim;
  in {
    environment.systemPackages = lib.mkBefore [ myNeovim ];
    environment.variables.EDITOR = lib.mkForce "${myNeovim}/bin/nvim";
  };

  perSystem = { pkgs, lib, ... }: let
    neovimExtraPkgs = [ pkgs.tree-sitter pkgs.dotnet-sdk pkgs.eslint_d pkgs.prettierd pkgs.alejandra pkgs.nixd pkgs.typescript-language-server pkgs.typescript pkgs.tailwindcss-language-server pkgs.tailwindcss_3 ];
    neovimGrammarPlugins = builtins.attrValues pkgs.vimPlugins.nvim-treesitter.grammarPlugins;
    neovimModule = { config, lib, wlib, ... }: {
      imports = [ wlib.wrapperModules.neovim ];
      settings.config_directory = lib.generators.mkLuaInline ''
        vim.fn.expand("$HOME/.dotfiles/config/nvim")
      '';
      extraPackages = neovimExtraPkgs;
      specs.treesitter-grammars = neovimGrammarPlugins;
    };
    wrapperEval = inputs.wrapper-modules.lib.evalModule [ neovimModule ];
  in {
    packages.myNeovim = wrapperEval.config.wrap { inherit pkgs; };
  };
}
