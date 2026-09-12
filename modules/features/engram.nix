{ self, inputs, ... }: {
  flake.nixosModules.engram = { config, pkgs, lib, ... }: let
    system = pkgs.stdenv.hostPlatform.system;
    gentleEngram = self.packages.${system}.gentle-engram;
    user = "ejverat";
    homeDir = config.users.users.${user}.home;
  in {
    # Engram server on PATH: the gentle-engram extension lazily spawns
    # `engram serve` (HTTP on 127.0.0.1:7437) when memory is used, and
    # `engram tui` is available to browse stored memories.
    environment.systemPackages = [ self.packages.${system}.engram ];

    # Register the Nix-built gentle-engram Pi package (mem_* tools) in pi's
    # global settings, additively, next to the gentle-pi entry. Same merge
    # policy as gentle-pi.nix: idempotent, preserves every other entry.
    system.activationScripts.piEngram = {
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
        if ${pkgs.jq}/bin/jq --arg pkg "${gentleEngram}" '
          .packages = (
            ((.packages // [])
              | map(select(
                  ((type == "string" and test("^/nix/store/[a-z0-9]{32}-gentle-engram$"))
                   or (type == "object" and ((.source? // "") | test("^/nix/store/[a-z0-9]{32}-gentle-engram$"))))
                  | not)))
            + [$pkg] | unique)
        ' "$settings" > "$tmp"; then
          # In-place write keeps the file owned by the user.
          ${pkgs.coreutils}/bin/cat "$tmp" > "$settings"
        else
          echo "pi-engram: could not merge into $settings; leaving it unchanged" >&2
        fi
        ${pkgs.coreutils}/bin/rm -f "$tmp"
      '';
    };
  };

  perSystem = { pkgs, inputs', ... }: {
    # Engram memory server: pure-Go (modernc.org/sqlite), SQLite + FTS5.
    packages.engram = pkgs.buildGoModule (finalAttrs: {
      pname = "engram";
      version = "1.20.0";

      src = pkgs.fetchFromGitHub {
        owner = "Gentleman-Programming";
        repo = "engram";
        tag = "v${finalAttrs.version}";
        hash = "sha256-qdKAll7N0HtJRbZYilzatVCUz1Tr+pqM217Y8O+Csjs=";
      };

      vendorHash = "sha256-O+pC4x4DKNUWr7Sx9iZOjK6a64wrQA4/lnjvkNLBX64=";
      subPackages = [ "cmd/engram" ];

      env.CGO_ENABLED = 0;
      ldflags = [ "-s" "-w" ];
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
    # tarball (no build step); only runtime dep is typebox.
    packages.gentle-engram = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
      pname = "gentle-engram";
      version = "0.1.12";

      src = pkgs.fetchurl {
        url = "https://registry.npmjs.org/gentle-engram/-/gentle-engram-${finalAttrs.version}.tgz";
        hash = "sha512-uSuLTmK5dq5mYCwKrrVLnEJUNGHBl5ptVsxxstP8sCnnWUQvg2dQC99NEapgMfQO7ni8u9vG5LF07p8do23MLQ==";
      };

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
