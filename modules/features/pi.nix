{ inputs, ... }: {
  flake.nixosModules.pi = { pkgs, lib, ... }: let
    # pi-coding-agent from the dedicated nixpkgs-pi pin: gentle-pi requires
    # pi >= 0.85.1 while the main nixpkgs pin still ships an older release.
    piPkgs = inputs.nixpkgs-pi.legacyPackages.${pkgs.stdenv.hostPlatform.system};

    # pi shells out to npm at startup for two things:
    #
    #   1. It reconciles the `npm:` entries in ~/.pi/agent/settings.json by
    #      running `npm install <pkg> --prefix ~/.pi/agent/npm
    #      --legacy-peer-deps`.
    #   2. It runs MCP servers from ~/.pi/agent/mcp.json whose `command` may
    #      be `npx` (the context7 entry uses it).
    #
    # The nixpkgs package wraps $out/bin/pi with only ripgrep and fd on PATH
    # (postFixup), so as soon as a `npm:` package was configured pi died on
    # *every* invocation -- including `pi --help` and `pi --version` -- with:
    #
    #   Error: spawn npm ENOENT
    #     spawnargs: [ 'install', 'pi-mcp-adapter', '--prefix',
    #                  '/home/<user>/.pi/agent/npm', '--legacy-peer-deps' ]
    #
    # Put nodejs on pi's PATH so `node`, `npm` and `npx` resolve. nodejs is
    # taken from the same nixpkgs revision as pi itself to avoid mixing the
    # two pins. No NPM_CONFIG_PREFIX is set on purpose: pi already passes an
    # explicit --prefix, and overriding npm's global prefix would only fight
    # the location pi actually reads packages back from.
    pi = pkgs.symlinkJoin {
      name = "pi-coding-agent-${piPkgs.pi-coding-agent.version}";
      paths = [ piPkgs.pi-coding-agent ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/pi \
          --prefix PATH : ${lib.makeBinPath [ piPkgs.nodejs ]}
      '';
    };
  in {
    environment.systemPackages = [ pi ];
  };
}
