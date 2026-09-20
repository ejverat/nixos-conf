# Shared provider-keys env paths.
#
# The NixOS host (chopper) renders the keys with root sops to a system path; the
# standalone host (gear5th) renders them with user sops under $HOME. Both the
# secrets module and the zsh wrapper need the path, and the wrapper packages are
# built in `perSystem`, which cannot read the NixOS config, so the path is a
# shared constant rather than a `nixosConf` option. Keeping it here stops the
# literal from being duplicated (and silently diverging) across four call sites.
#
# Lives under modules/lib/ with a leading underscore so import-tree skips it.
{
  # Absolute path on NixOS, rendered by modules/features/secrets.nix and sourced
  # by the `myZsh` wrapper.
  providerKeysEnvNixos = "/run/secrets/rendered/pi-provider-keys.env";
  # Path relative to $HOME on non-NixOS hosts, rendered by the secrets home
  # module and sourced by the `myZshPortable` wrapper.
  providerKeysEnvPortable = ".config/pi-provider-keys.env";
}
