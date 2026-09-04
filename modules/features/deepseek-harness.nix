{ self, inputs, pkgs, ... }: {
  flake.nixosModules.deepseek-harness = { pkgs, ... }: {
    environment.systemPackages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.deepseek-harness
    ];
  };

  perSystem = { pkgs, inputs', ... }: let
    pnpm11 = inputs'.nixpkgs-pnpm.legacyPackages;
    pnpmExe = pnpm11.pnpm_11.override { version = "11.7.0"; hash = "sha256-3q+n7JihIYtqBHKJuS++I5XB4i00lbtxFlMBMhjuFe4="; };
  in {
    packages.deepseek-harness = pkgs.stdenv.mkDerivation (finalAttrs: {
      pname = "deepseek-harness";
      version = "0.1.0-rc.5";

      src = pkgs.fetchFromGitHub {
        owner = "deepseek-ai";
        repo = "deepseek-harness";
        rev = "abe560f81edebe5f6a5b62706ff502daa0dccd40";
        sha256 = "sha256-ZPGCNoPXVjP76Tm/tFPDX2X95cd83M4iHLmVP5dR+Ps=";
      };

      __structuredAttrs = true;
      strictDeps = true;

      pnpmDeps = pnpm11.fetchPnpmDeps {
        inherit (finalAttrs) pname version src;
        pnpm = pnpm11.pnpm;
        fetcherVersion = 4;
        hash = "sha256-aySHq0ywTMM5q7YuGHZrV3yQE3bwppgGfWH3wRnHCXk=";
      };

      nativeBuildInputs = [
        pnpmExe
        pkgs.nodejs_26
        pnpm11.pnpmConfigHook
        pkgs.makeBinaryWrapper
        pkgs.python3
      ];

      buildInputs = [
        pkgs.nodejs_26
        pkgs.bubblewrap
      ];

      buildPhase = ''
        runHook preBuild
        pnpm run build
        runHook postBuild
      '';

      postBuild = ''
        for dir in $(find node_modules -type d -name "node-pty"); do
          cd "$dir"
          npm_config_nodedir="${pkgs.nodejs_26}" ${pkgs.nodejs_26}/bin/npm run install
          cd "$OLDPWD"
        done
      '';

      installPhase = ''
        runHook preInstall

        mkdir -p "$out"
        cp -r node_modules packages python vendor website native apps "$out/"
        rm -f $out/node_modules/.pnpm/node_modules/dsh-examples
        rm -f $out/node_modules/.pnpm/node_modules/dsh-jsonrpc-agent-pkg

        runHook postInstall
      '';

      postInstall = ''
        mkdir -p "$out/bin"
        makeBinaryWrapper ${pkgs.nodejs_26}/bin/node "$out/bin/dsh" \
          --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.bubblewrap ]} \
          --add-flags "--expose-internals $out/apps/cli/lib/bin.js"
      '';

      meta = {
        mainProgram = "dsh";
        homepage = "https://github.com/deepseek-ai/deepseek-harness/";
        description = "An open-source agent harness developed by DeepSeek AI.";
        license = pkgs.lib.licenses.mit;
        platforms = pkgs.lib.platforms.linux;
        sourceProvenance = with pkgs.lib.sourceTypes; [ fromSource ];
      };
    });
  };
}
