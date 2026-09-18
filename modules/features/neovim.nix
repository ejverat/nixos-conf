{ self, inputs, ... }: {
  flake.nixosModules.neovim = { config, pkgs, lib, ... }: let
    myNeovim = self.packages.${pkgs.stdenv.hostPlatform.system}.myNeovim;
    mmdr = inputs.mermaid-rs-renderer.packages.${pkgs.stdenv.hostPlatform.system}.default;
  in {
    environment.systemPackages = lib.mkBefore [ myNeovim mmdr ];
    environment.variables.EDITOR = lib.mkForce "${myNeovim}/bin/nvim";
  };

  # Portable user layer (non-NixOS hosts, e.g. gear5th/Debian). The wrapper is
  # the same perSystem package; the raw config lives in the vendored dotfiles
  # materialized at $HOME/.dotfiles/config/nvim by the dotfiles home module.
  flake.homeModules.neovim = { pkgs, lib, flakeSelf, flakeInputs, ... }: let
    system = pkgs.stdenv.hostPlatform.system;
    myNeovim = flakeSelf.packages.${system}.myNeovim;
    mmdr = flakeInputs.mermaid-rs-renderer.packages.${system}.default;
  in {
    home.packages = [ myNeovim mmdr ];
    home.sessionVariables.EDITOR = "${myNeovim}/bin/nvim";
  };

  perSystem = { pkgs, lib, ... }: let
    neovimExtraPkgs = [ pkgs.tree-sitter pkgs.dotnet-sdk pkgs.eslint_d pkgs.prettierd pkgs.alejandra pkgs.nixd pkgs.typescript-language-server pkgs.typescript pkgs.tailwindcss-language-server pkgs.tailwindcss_3 pkgs.cargo pkgs.rustc pkgs.fd pkgs.imagemagick pkgs.ueberzugpp ]; # imagemagick: image.nvim magick_cli processor; ueberzugpp: ueberzug backend (WezTerm no renderiza kitty)
    neovimGrammarPlugins = builtins.attrValues pkgs.vimPlugins.nvim-treesitter.grammarPlugins;
    neovimModule = { config, lib, wlib, ... }: {
      imports = [ wlib.wrapperModules.neovim ];
      settings.config_directory = lib.generators.mkLuaInline ''
        vim.fn.expand("$HOME/.dotfiles/config/nvim")
      '';
      runtimePkgs = neovimExtraPkgs;
      # Prefix clang-tools (clangd 21) so it shadows any older clangd on the outer
      # PATH (e.g. the FHS devshell's clangd 19, which segfaults on UE headers).
      prefixVar = [
        [ "PATH" ":" (pkgs.lib.makeBinPath [ pkgs.clang-tools ]) ]
      ];
      specs.treesitter-grammars = neovimGrammarPlugins;
      # Neovim's python3 remote-plugin host. `pynvim` is added automatically by
      # wrapper-modules; `jupyter_client` (molten kernel comms) and `pillow`
      # (MoltenImagePopup) are the extra python deps molten-nvim needs on the host.
      hosts.python3.withPackages = pp: [ pp.jupyter-client pp.pillow ];
    };
    wrapperEval = inputs.wrapper-modules.lib.evalModule [ neovimModule ];
  in {
    packages.myNeovim = wrapperEval.config.wrap { inherit pkgs; };
  };
}
