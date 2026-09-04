{ self, inputs, ... }: {
  flake.nixosModules.neovim = { config, pkgs, lib, ... }: let
    myNeovim = self.packages.${pkgs.stdenv.hostPlatform.system}.myNeovim;
    mmdr = inputs.mermaid-rs-renderer.packages.${pkgs.stdenv.hostPlatform.system}.default;
  in {
    environment.systemPackages = lib.mkBefore [ myNeovim mmdr ];
    environment.variables.EDITOR = lib.mkForce "${myNeovim}/bin/nvim";
  };

  perSystem = { pkgs, lib, ... }: let
    neovimExtraPkgs = [ pkgs.tree-sitter pkgs.dotnet-sdk pkgs.eslint_d pkgs.prettierd pkgs.alejandra pkgs.nixd pkgs.typescript-language-server pkgs.typescript pkgs.tailwindcss-language-server pkgs.tailwindcss_3 pkgs.cargo pkgs.rustc pkgs.fd ];
    neovimGrammarPlugins = builtins.attrValues pkgs.vimPlugins.nvim-treesitter.grammarPlugins;
    neovimModule = { config, lib, wlib, ... }: {
      imports = [ wlib.wrapperModules.neovim ];
      settings.config_directory = lib.generators.mkLuaInline ''
        vim.fn.expand("$HOME/.dotfiles/config/nvim")
      '';
      extraPackages = neovimExtraPkgs;
      # Prefix clang-tools (clangd 21) so it shadows any older clangd on the outer
      # PATH (e.g. the FHS devshell's clangd 19, which segfaults on UE headers).
      prefixVar = [
        [ "PATH" ":" (pkgs.lib.makeBinPath [ pkgs.clang-tools ]) ]
      ];
      specs.treesitter-grammars = neovimGrammarPlugins;
    };
    wrapperEval = inputs.wrapper-modules.lib.evalModule [ neovimModule ];
  in {
    packages.myNeovim = wrapperEval.config.wrap { inherit pkgs; };
  };
}
