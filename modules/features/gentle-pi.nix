{ self, inputs, ... }: let
  # Shared shell bodies for the NixOS/home-manager activation pair (see
  # modules/lib/_pi-activation.nix and _gentle-profile.nix). Both variants used
  # to carry near-identical copies of the seeding, the ownership fixups and the
  # settings.json bootstrap.
  piActivation = import ../lib/_pi-activation.nix;
  gentleProfile = import ../lib/_gentle-profile.nix;

  # gentle-ai release pinned by gentle-pi v4.3.0 itself
  # (scripts/gentle-ai-installer.mjs, INSTALLER_VERSION). The binary is a
  # static Go executable, so the official signed release runs fine on NixOS
  # and passes gentle-pi's strict package-local integrity verification.
  #
  # This version may never drift from the gentle-pi tag: the installer fails
  # closed with GENTLE_AI_VERSION_MISMATCH when the binary does not report
  # INSTALLER_VERSION, and `pi install` would otherwise re-download it.
  gentleAiVersion = "4.2.0";
  gentleAiAsset = "gentle-ai_4.2.0_linux_amd64.tar.gz";
  # Both digests are transcribed from that release's own asset table
  # (`asset(name, sha256, binarySha256, executable)`) and were re-derived from
  # the downloaded archive before pinning.
  gentleAiAssetSha256 = "552c1642fd10f5d96cfe9bb1cc3b66b30eb47d3074cc7ca0559b598eb086defc";
  gentleAiBinarySha256 = "9212c7b16ea9abfe93e3a16b29d8390e7762b5c07730cf05df1f3e7892ff96a4";
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
    # store path is `<pname>-<version>` (e.g. ...-gentle-pi-3.7.0), so an
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

    # gentle-profile is this repository's own routing tool, vendored in
    # dotfiles/pi-gentle-ai/ and seeded here. Neither the gentle-pi package nor
    # gentle-ai ships it: the string appears nowhere in gentle-pi 4.3.0, gentle-ai
    # 4.2.0 exposes no profile command in `--help`, and `gentle-ai sync` in a fresh
    # home writes only state/telemetry. What the Nix package does ship is the
    # runtime binary and the pi extension, so a fresh host has nothing to link
    # (that is what happened on gear5th). Seed the vendored copy when it is
    # missing — never overwrite, because a host that already has a locally adapted
    # copy must keep it (chopper's copy predates the vendoring) — make sure it is
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
        hash = "sha256-VSwWQv0Q9dls/puxzDtmsw60fTB0zHygVZtZjrCG3vw=";
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
      version = "4.3.0";

      # The upstream GitHub repository was renamed to `gentle-shell` (the npm
      # package is still `gentle-pi`, and gentle-pi's own self-detection paths
      # still use the old repo name). `repo` deliberately keeps the old name:
      # GitHub's rename redirect resolves it, and the pinned tag plus hash are
      # content-addressed either way. Switching the name would only rename the
      # source store path; revisit if the redirect ever stops resolving.
      src = pkgs.fetchFromGitHub {
        owner = "Gentleman-Programming";
        repo = "gentle-pi";
        tag = "v${finalAttrs.version}";
        hash = "sha256-rmuIk4IudViiz4nDJ646lCOHLfHIAboKmH/RdIqkpf4=";
      };

      __structuredAttrs = true;
      strictDeps = true;

      pnpmDeps = pnpm11.fetchPnpmDeps {
        inherit (finalAttrs) pname version src;
        pnpm = pnpm11.pnpm;
        fetcherVersion = 4;
        # Recomputed for v4.3.0: its pnpm-lock.yaml (lockfileVersion 9.0) is not
        # the tree the v3.x pin resolved, so the old hash no longer matches and
        # the dependency set moved from pi-tui + pi-pretty to pi-pretty alone.
        hash = "sha256-7/qFx9LTDo717xj+iojzyx2gXiUW20B8CmTGN9yO9NI=";
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

        # Same file set as the published npm tarball. v4.3.0 package.json
        # "files" is: assets bin contracts docs extensions lib prompts runtime
        # scripts skills tests themes README.md, and npm always adds
        # package.json and LICENSE. Keep this list in step with "files":
        # `bin/` holds `gentle-shell`, the launcher package.json declares.
        mkdir -p $out
        cp -r assets bin contracts docs extensions lib prompts runtime scripts skills tests themes package.json README.md LICENSE $out/

        # Runtime deps only: v4.3.0 declares a single non-peer dependency,
        # @heyhuynhgiabuu/pi-pretty.
        pnpm prune --prod --ignore-scripts
        # prune leaves stale .bin shims pointing at removed devDependencies;
        # pi imports libraries only, it never uses the .bin shims.
        rm -rf node_modules/.bin
        cp -r node_modules $out/

        # v3.7.0 had @earendil-works/pi-tui as a real dependency; v4.3.0 declares
        # only @heyhuynhgiabuu/pi-pretty and makes pi-coding-agent, pi-ai, pi-tui
        # optional peers (plus a hard typebox peer). pnpm auto-installs those
        # peers, so a second copy of the SDK lands next to the Nix-pinned pi
        # (both resolve to 1.2.0 today, but only the nixpkgs-pi pin is
        # maintained). Drop the SDK copy so the pinned pi stays the single
        # source of truth:
        #
        #   - Nothing needs it at runtime. pi aliases @earendil-works/* to its
        #     own copies for every extension load (dist/core/extensions/
        #     loader.js, getAliases), which is how the extensions/*.ts imports
        #     resolve; the auto-installed pi-tui/pi-ai/pi-agent-core copies are
        #     likewise shadowed and unused.
        #   - gentle-shell's resolveBundledCli() (bin/gentle-shell.mjs) is the
        #     one real consumer: it runs
        #     import.meta.resolve("@earendil-works/pi-coding-agent") and, when
        #     that resolves, launches <that copy>/dist/bundle/cli.js under node
        #     in preference to `pi` on PATH (resolvePiRuntime in
        #     lib/gentle-shell-launcher.ts). Keeping the copy would therefore
        #     let a flake-unpinned pi shadow the pinned one. Removing it makes
        #     the resolution throw ERR_MODULE_NOT_FOUND and the launcher fall
        #     back to the pinned `pi` on PATH, which is what we want.
        rm -rf $out/node_modules/@earendil-works/pi-coding-agent

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
