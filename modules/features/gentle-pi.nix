{ self, inputs, ... }: let
  # Shared shell bodies for the NixOS/home-manager activation pair (see
  # modules/lib/_pi-activation.nix and _gentle-profile.nix). Both variants used
  # to carry near-identical copies of the seeding, the ownership fixups and the
  # settings.json bootstrap.
  piActivation = import ../lib/_pi-activation.nix;
  gentleProfile = import ../lib/_gentle-profile.nix;

  # gentle-ai release pinned by gentle-pi v3.2.0 itself
  # (scripts/gentle-ai-installer.mjs, INSTALLER_VERSION). The binary is a
  # static Go executable, so the official signed release runs fine on NixOS
  # and passes gentle-pi's strict package-local integrity verification.
  gentleAiVersion = "3.1.0";
  gentleAiAsset = "gentle-ai_3.1.0_linux_amd64.tar.gz";
  gentleAiAssetSha256 = "dc55c44a2eb46212a38eca0dfd4d778481ec37e765f40d5a0752d03c28e1ee49";
  gentleAiBinarySha256 = "70e335d25809a0d358c12f48b2f0d1da00741e725584ceeb8c1318c60d0a6e9e";
in {
  flake.nixosModules.gentle-pi = { config, pkgs, lib, ... }: let
    system = pkgs.stdenv.hostPlatform.system;
    package = self.packages.${system}.gentle-pi;
    user = config.nixosConf.user.name;
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
      text = gentleProfile {
        inherit lib homeDir;
        vendored = ../../dotfiles/pi-gentle-ai/gentle-profile;
        owner = "${user}:users";
      };
    };

    # Register the Nix-built gentle-pi in pi's global settings. Pi has no
    # settings.d support, so merge the entry additively into the existing
    # user-writable settings.json (idempotent; other entries are preserved).
    # Do NOT also `pi install npm:gentle-pi`: that would load it twice.
    #
    # The prune regex MUST tolerate the `-<version>` suffix: a derivation's
    # store path is `<pname>-<version>` (e.g. ...-gentle-pi-3.2.0), so an
    # anchored `-gentle-pi$` matches nothing and stale versions accumulate in
    # settings.json. Pi then loads two copies of the same extensions and
    # aborts startup with `Tool "<name>" conflicts with ...`.
    system.activationScripts.piGentlePi = {
      deps = [ "users" "groups" ];
      text = piActivation {
        inherit lib pkgs homeDir package;
        pkgRegex = "^/nix/store/[a-z0-9]{32}-gentle-pi(-[0-9][^/]*)?$";
        owner = "${user}:users";
      };
    };
  };

  # Portable user layer (non-NixOS hosts, e.g. gear5th/Debian). home-manager
  # activations already run as the user, so there is no ownership juggling; the
  # ~/.local/bin entry for `gentle-profile` lives in the portable zsh wrapper
  # (see the zsh module), matching chopper's session variable.
  flake.homeModules.gentle-pi = { config, pkgs, lib, flakeSelf, ... }: let
    package = flakeSelf.packages.${pkgs.stdenv.hostPlatform.system}.gentle-pi;
  in {
    # NOTE: the package is deliberately NOT added to home.packages. Two reasons:
    #   - pi loads it by the path written into settings.json, so it needs no PATH
    #     entry;
    #   - buildEnv rejects it alongside gentle-engram because both ship a
    #     top-level README.md ("two given paths contain a conflicting subpath").
    # The activation script below references the store path, which is what puts
    # it in the generation's closure — and the generation is GC-rooted by
    # home-manager.

    # The gentle-profile script (linked below) hard-requires perl on PATH
    # (`command -v perl >/dev/null 2>&1 || die "falta perl en el PATH"`).
    # Debian ships perl in its base system, but pinning it here keeps gear5th
    # deterministic and documents the dependency next to what needs it.
    home.packages = [ pkgs.perl ];

    # The gentle-ai runtime writes this script into its config home on first use,
    # but the Nix package only ships the runtime binary and the pi extension, so a
    # fresh host can end up without it (that is what happened on gear5th: the
    # activation had nothing to link). Seed the vendored copy when it is missing —
    # never overwrite, so a runtime-provided version always wins — make sure it is
    # runnable, and link it so `gentle-profile` resolves by bare name.
    # `pi --version` does NOT load extensions: only a real session materializes
    # runtime files, which is why the seeding matters.
    home.activation.gentleProfileLink = lib.hm.dag.entryAfter [ "writeBoundary" ] (gentleProfile {
      inherit lib;
      homeDir = config.home.homeDirectory;
      vendored = ../../dotfiles/pi-gentle-ai/gentle-profile;
    });

    # Same additive merge as the NixOS variant: pi rewrites this file at
    # runtime, so it cannot be managed declaratively.
    home.activation.piGentlePi = lib.hm.dag.entryAfter [ "writeBoundary" ] (piActivation {
      inherit lib pkgs package;
      homeDir = config.home.homeDirectory;
      pkgRegex = "^/nix/store/[a-z0-9]{32}-gentle-pi(-[0-9][^/]*)?$";
    });
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
        hash = "sha256-3FXESi60YhKjjsoN/U13hIHsN+dl9A1aB1LQPCjh7kk=";
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
      version = "3.2.0";

      src = pkgs.fetchFromGitHub {
        owner = "Gentleman-Programming";
        repo = "gentle-pi";
        tag = "v${finalAttrs.version}";
        hash = "sha256-vN+esM/GaVMmCAs6j4JhVBDoeg60OacDW+Rw7Kh4aFg=";
      };

      __structuredAttrs = true;
      strictDeps = true;

      pnpmDeps = pnpm11.fetchPnpmDeps {
        inherit (finalAttrs) pname version src;
        pnpm = pnpm11.pnpm;
        fetcherVersion = 4;
        hash = "sha256-MTi1ZLE4pX4YgDlxnvy3Zo7yZQT6gquYISJSIae2eAk=";
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
