{ self, inputs, ... }: let
  # gentle-ai release pinned by gentle-pi v2.5.0 itself
  # (scripts/gentle-ai-installer.mjs, INSTALLER_VERSION). The binary is a
  # static Go executable, so the official signed release runs fine on NixOS
  # and passes gentle-pi's strict package-local integrity verification.
  gentleAiVersion = "2.7.0";
  gentleAiAsset = "gentle-ai_2.7.0_linux_amd64.tar.gz";
  gentleAiAssetSha256 = "ff765a183247fe31d4739ff6df3d6874740979987ea310de3856c8a6e85375e9";
  gentleAiBinarySha256 = "8748b9f18c05a831692abc0ae560fdc50a4e4c8f492705edcce7f65e067a7b12";
in {
  flake.nixosModules.gentle-pi = { config, pkgs, lib, ... }: let
    system = pkgs.stdenv.hostPlatform.system;
    package = self.packages.${system}.gentle-pi;
    user = "ejverat";
    homeDir = config.users.users.${user}.home;
  in {
    # Make ~/.local/bin reachable so `gentle-profile` resolves by bare name.
    #
    # `environment.localBinInPath = true` is deliberately NOT used here: that
    # option only appends `export PATH="$HOME/.local/bin:$PATH"` to
    # /etc/profile (nixos/modules/config/shells-environment.nix:265), and this
    # host's shell never reads that file. The login/interactive shell is the
    # wrapper-modules zsh with `skipGlobalRC = true`, so /etc/zshrc is skipped
    # too (verified: __ETC_ZSHRC_SOURCED is unset, __NIXOS_SET_ENVIRONMENT_DONE
    # is 1), and /etc/zprofile does not source /etc/profile either.
    #
    # The chain this zsh actually follows is:
    #   $ZDOTDIR/.zshenv -> /etc/zshenv -> /etc/set-environment
    # and `environment.sessionVariables` is exactly what lands in
    # /etc/set-environment (shells-environment.nix:231 merges it into
    # environment.variables). PATH is assembled with lib.concatLists over the
    # absolute variables plus the profile-relative ones
    # (programs/environment.nix sets PATH = [ "/bin" ] profile-relative), so
    # this entry is prepended rather than clobbering the NixOS profile paths.
    environment.sessionVariables.PATH = [ "$HOME/.local/bin" ];

    # Keep the gentle-profile switcher reachable on a fresh machine. The script
    # itself lives in pi's user-writable runtime state, so the link is created
    # only once that file exists. Never fatal: a missing script must not break
    # system activation.
    system.activationScripts.gentleProfileLink = {
      deps = [ "users" ];
      text = ''
        src="${homeDir}/.pi/gentle-ai/gentle-profile"
        dst="${homeDir}/.local/bin/gentle-profile"

        if [ -x "$src" ]; then
          mkdir -p "$(dirname "$dst")"
          ln -sfn "$src" "$dst"
          chown -h ${user}:users "$dst" 2>/dev/null || true
          chown ${user}:users "$(dirname "$dst")" 2>/dev/null || true
        else
          echo "gentle-profile: $src does not exist yet; skipping link" >&2
        fi
      '';
    };

    # Register the Nix-built gentle-pi in pi's global settings. Pi has no
    # settings.d support, so merge the entry additively into the existing
    # user-writable settings.json (idempotent; other entries are preserved).
    # Do NOT also `pi install npm:gentle-pi`: that would load it twice.
    system.activationScripts.piGentlePi = {
      deps = [ "users" "groups" ];
      text = ''
        agentDir="${homeDir}/.pi/agent"
        settings="$agentDir/settings.json"

        if [ ! -d "$agentDir" ]; then
          mkdir -p "$agentDir"
          chown -R ${user}:users "${homeDir}/.pi"
        fi

        if [ ! -f "$settings" ]; then
          echo '{}' > "$settings"
          chown ${user}:users "$settings"
        fi

        tmp=$(${pkgs.coreutils}/bin/mktemp)
        if ${pkgs.jq}/bin/jq --arg pkg "${package}" '
          .packages = (
            ((.packages // [])
              | map(select(
                  ((type == "string" and test("^/nix/store/[a-z0-9]{32}-gentle-pi$"))
                   or (type == "object" and ((.source? // "") | test("^/nix/store/[a-z0-9]{32}-gentle-pi$"))))
                  | not)))
            + [$pkg] | unique)
        ' "$settings" > "$tmp"; then
          # In-place write keeps the file owned by the user.
          ${pkgs.coreutils}/bin/cat "$tmp" > "$settings"
        else
          echo "pi-gentle-pi: could not merge into $settings; leaving it unchanged" >&2
        fi
        ${pkgs.coreutils}/bin/rm -f "$tmp"
      '';
    };
  };

  perSystem = { pkgs, inputs', ... }: let
    pnpm11 = inputs'.nixpkgs-pnpm.legacyPackages;
    pnpmExe = pnpm11.pnpm_11.override {
      version = "11.7.0";
      hash = "sha256-3q+n7JihIYtqBHKJuS++I5XB4i00lbtxFlMBMhjuFe4=";
    };

    # Official signed gentle-ai release asset, exactly what gentle-pi's
    # postinstall would download, plus the canonical integrity manifest the
    # installer writes (byte-identical JSON key order matters).
    gentleAiBundle = pkgs.stdenvNoCC.mkDerivation {
      pname = "gentle-ai-bundle";
      version = gentleAiVersion;

      src = pkgs.fetchurl {
        url = "https://github.com/Gentleman-Programming/gentle-ai/releases/download/v${gentleAiVersion}/${gentleAiAsset}";
        hash = "sha256-/3ZaGDJH/jHUc5/23z1odHQJeZh+oxDeOFbIpuhTdek=";
      };

      sourceRoot = ".";

      installPhase = ''
        runHook preInstall
        install -Dm755 gentle-ai $out/gentle-ai
        printf '%s\n' '{"version":"${gentleAiVersion}","asset":"${gentleAiAsset}","assetSha256":"${gentleAiAssetSha256}","binarySha256":"${gentleAiBinarySha256}"}' > $out/integrity.json
        runHook postInstall
      '';
    };
  in {
    packages.gentle-pi = pkgs.stdenv.mkDerivation (finalAttrs: {
      pname = "gentle-pi";
      version = "2.5.0";

      src = pkgs.fetchFromGitHub {
        owner = "Gentleman-Programming";
        repo = "gentle-pi";
        tag = "v${finalAttrs.version}";
        hash = "sha256-i/Sbg7xfCx5YLTyvL4cYPlvBL/qRhwPVz5Gallbv/Yk=";
      };

      __structuredAttrs = true;
      strictDeps = true;

      pnpmDeps = pnpm11.fetchPnpmDeps {
        inherit (finalAttrs) pname version src;
        pnpm = pnpm11.pnpm;
        fetcherVersion = 4;
        hash = "sha256-i7xs9URp+tRWVlnivUk9e4bgW3WnP1biwwsgvQI1CoI=";
      };

      nativeBuildInputs = [
        pnpmExe
        pkgs.nodejs
        pnpm11.pnpmConfigHook
      ];

      # Nothing to compile: pnpmConfigHook already ran
      # `pnpm install --offline --ignore-scripts --frozen-lockfile`.
      # --ignore-scripts is intentional: the postinstall downloads the
      # gentle-ai binary (provided declaratively below) and edits pi's
      # global settings (only allowed for pi's own npm installs anyway).
      dontBuild = true;

      installPhase = ''
        runHook preInstall

        # Same file set as the published npm tarball (package.json "files").
        mkdir -p $out
        cp -r assets contracts docs extensions lib prompts runtime scripts skills tests themes package.json README.md LICENSE $out/

        # Runtime deps only (@earendil-works/pi-tui, @heyhuynhgiabuu/pi-pretty).
        pnpm prune --prod --ignore-scripts
        # prune leaves stale .bin shims pointing at removed devDependencies;
        # pi imports libraries only, it never uses the .bin shims.
        rm -rf node_modules/.bin
        cp -r node_modules $out/

        # Package-local gentle-ai runtime, hash-identical to the one the
        # postinstall would have fetched, so the strict resolver accepts it.
        mkdir -p $out/.gentle-ai/v${gentleAiVersion}
        install -Dm755 ${gentleAiBundle}/gentle-ai $out/.gentle-ai/v${gentleAiVersion}/gentle-ai
        install -Dm644 ${gentleAiBundle}/integrity.json $out/.gentle-ai/v${gentleAiVersion}/integrity.json

        runHook postInstall
      '';

      meta = {
        homepage = "https://github.com/Gentleman-Programming/gentle-pi";
        description = "Turn Pi into el Gentleman: senior-architect harness with SDD/OpenSpec, subagents, TDD evidence and review guardrails";
        license = pkgs.lib.licenses.mit;
        platforms = [ "x86_64-linux" ];
      };
    });
  };
}
