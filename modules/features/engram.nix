{ self, inputs, ... }: let
  # Shared shell body for the NixOS/home-manager activation pair. See
  # modules/lib/_pi-activation.nix.
  piActivation = import ../lib/_pi-activation.nix;
in {
  flake.nixosModules.engram = { config, pkgs, lib, ... }: let
    system = pkgs.stdenv.hostPlatform.system;
    gentleEngram = self.packages.${system}.gentle-engram;
    user = config.nixosConf.user.name;
    homeDir = config.users.users.${user}.home;
  in {
    # Engram server on PATH: the gentle-engram extension lazily spawns
    # `engram serve` (HTTP on 127.0.0.1:7437) when memory is used, and
    # `engram tui` is available to browse stored memories.
    environment.systemPackages = [ self.packages.${system}.engram ];

    # Register the Nix-built gentle-engram Pi package (mem_* tools) in pi's
    # global settings, additively, next to the gentle-pi entry. Same merge
    # policy as gentle-pi.nix: idempotent, preserves every other entry.
    #
    # As in gentle-pi.nix, the prune regex must tolerate the `-<version>`
    # suffix of the store path (...-gentle-engram-0.1.12), otherwise old
    # versions are never removed and pi fails with duplicate tool conflicts.
    system.activationScripts.piEngram = {
      deps = [ "users" "groups" ];
      text = piActivation {
        inherit lib pkgs homeDir;
        package = gentleEngram;
        pkgRegex = "^/nix/store/[a-z0-9]{32}-gentle-engram(-[0-9][^/]*)?$";
        owner = "${user}:users";
      };
    };
  };

  # Portable user layer (non-NixOS hosts, e.g. gear5th/Debian): the server on
  # PATH (the extension lazily spawns `engram serve`) plus the same additive
  # registration of the pi extension.
  flake.homeModules.engram = { config, pkgs, lib, flakeSelf, ... }: let
    system = pkgs.stdenv.hostPlatform.system;
    engram = flakeSelf.packages.${system}.engram;
    gentleEngram = flakeSelf.packages.${system}.gentle-engram;
  in {
    # Only the server CLI goes on PATH: the gentle-engram extension is loaded by
    # the path written into settings.json (see the note in gentle-pi.nix about
    # why both extensions cannot sit in home.packages at once).
    home.packages = [ engram ];

    home.activation.piEngram = lib.hm.dag.entryAfter [ "writeBoundary" ] (piActivation {
      inherit lib pkgs;
      homeDir = config.home.homeDirectory;
      package = gentleEngram;
      pkgRegex = "^/nix/store/[a-z0-9]{32}-gentle-engram(-[0-9][^/]*)?$";
    });
  };

  perSystem = { pkgs, inputs', ... }: {
    # Engram memory server: pure-Go (modernc.org/sqlite), SQLite + FTS5.
    #
    # This server and the `gentle-engram` extension move together, never alone:
    # the extension requires instance identity from this binary, and v3.0.0 in
    # turn requires an explicit `expected_project` on every observation update
    # and delete, which only the matching extension sends. See the note on the
    # extension pin below.
    packages.engram = pkgs.buildGoModule (finalAttrs: {
      pname = "engram";
      version = "3.0.0";

      src = pkgs.fetchFromGitHub {
        owner = "Gentleman-Programming";
        repo = "engram";
        tag = "v${finalAttrs.version}";
        hash = "sha256-W5LNPxS4qa0fo/ejVQueR13cSLrtVydnsdgLGgIZ4uI=";
      };

      # v3.0.0's module closure (it now pulls the cloud/dashboard dependencies).
      vendorHash = "sha256-roVQ+K9Hsz0qi61f+zzb+JvgleOmBHSMcKfhwhI0snQ=";
      subPackages = [ "cmd/engram" ];

      env.CGO_ENABLED = 0;
      # `-X main.version` is the ldflag .goreleaser.yaml uses; cmd/engram/main.go
      # declares `var version = "dev"`, so without it the binary cannot state its
      # own version and answers "Could not check for updates". The extension and
      # `engram doctor` both reason about the server's version.
      ldflags = [ "-s" "-w" "-X" "main.version=${finalAttrs.version}" ];
      doCheck = false;

      meta = {
        homepage = "https://github.com/Gentleman-Programming/engram";
        description = "Persistent memory for AI coding agents: local-first SQLite + FTS5 brain with HTTP and MCP servers";
        license = pkgs.lib.licenses.mit;
        platforms = [ "x86_64-linux" ];
        mainProgram = "engram";
      };
    });

    # gentle-engram: the Pi extension that exposes compact mem_* tools and
    # captures session events into the Engram HTTP server. Published npm
    # tarball (no build step).
    #
    # This extension and the `engram` server above are one unit: bump them
    # together, never alone. Both couplings were learned the hard way:
    #   - From 0.1.16 the extension requires the binary to answer `instance-id`
    #     (instance identity, >= v2.0.0-rc.11) and refuses to initialize the
    #     memory provider otherwise. Pairing 0.1.16 with the 1.20.0 server broke
    #     every mem_* tool.
    #   - 0.2.0 sends `expected_project` on `PATCH`/`DELETE /observations/{id}`,
    #     which is what the 3.0.0 server began requiring. The mirror case is just
    #     as broken: 3.0.0 with a 0.1.x extension fails mem_update and mem_delete.
    # The 3.0.0 + 0.2.0 pair was validated against a copy of the live database
    # through ENGRAM_DATA_DIR, with `engram doctor` and a write round trip, before
    # either pin moved.
    packages.gentle-engram = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
      pname = "gentle-engram";
      version = "0.2.0";

      src = pkgs.fetchurl {
        url = "https://registry.npmjs.org/gentle-engram/-/gentle-engram-${finalAttrs.version}.tgz";
        hash = "sha512-c/1mAVfkGc6M5C8cGjwqCRo7cgckI26fXczDVLnT1cwLrw6Am//IFUxLZM6Gs5LOFhp0OARY+GJ+XQ/An4YAZA==";
      };

      # 0.2.0 declares typebox as a peer, and pi aliases that specifier to its own
      # copy at load time. The local install is kept anyway so the package stays
      # self-contained if it is ever loaded without that alias.
      typebox = pkgs.fetchurl {
        url = "https://registry.npmjs.org/typebox/-/typebox-1.3.30.tgz";
        hash = "sha512-vRmBLzlaq9O9dvfGmI5CssLGvDC/R594kH6N/Q1uUU5VPO3PTgQMlWe/UVNdNVTr2EET+FX8BWZkFdYgxTglbQ==";
      };

      sourceRoot = ".";

      installPhase = ''
        runHook preInstall
        mkdir -p $out
        cp -r package/. $out/
        # Package-local dependency, same layout a `pi install npm:gentle-engram`
        # would produce. Optional peers (@earendil-works/pi-tui, pi-coding-agent)
        # are intentionally absent: pi bundles them for extensions.
        mkdir -p $out/node_modules/typebox
        tar -xzf $typebox --strip-components=1 -C $out/node_modules/typebox
        runHook postInstall
      '';

      meta = {
        homepage = "https://github.com/Gentleman-Programming/engram";
        description = "Engram persistent memory integration for the Pi coding agent";
        license = pkgs.lib.licenses.mit;
        platforms = [ "x86_64-linux" ];
      };
    });
  };
}
