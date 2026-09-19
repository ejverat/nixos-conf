# Encrypted secrets for pi's model providers.
#
# The age identity is the ed25519 SSH host key: `sops.age.sshKeyPaths` already
# defaults to the ed25519 entries of `services.openssh.hostKeys`, and
# `services.openssh.enable` is on in modules/hosts/chopper/configuration.nix.
# That means no age key file to generate, store, or leak.
#
# The recipient below is derived (not secret) from the host's public key:
#   ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub
# Re-derive it if the SSH host key is ever regenerated.
{
  self,
  inputs,
  ...
}: {
  flake.nixosModules.secrets = {
    config,
    pkgs,
    lib,
    ...
  }: let
    # Path of the rendered env file. modules/features/zsh.nix sources this exact
    # path from the wrapper's zshenv. Keep the two in sync.
    renderedEnv = "/run/secrets/rendered/pi-provider-keys.env";

    # Editing the encrypted file needs the age identity, which is the SSH host
    # key and is therefore root-only. This wrapper converts it in memory into a
    # short-lived 0600 file so `sops` can decrypt, then shreds it on exit. The
    # key material never reaches the terminal or the shell history.
    sopsEdit = pkgs.writeShellApplication {
      name = "sops-edit";
      runtimeInputs = [pkgs.sops pkgs.coreutils];
      text = ''
        set -euo pipefail

        host_key=/etc/ssh/ssh_host_ed25519_key
        target="''${1:-secrets/secrets.yaml}"

        # writeShellApplication restricts PATH to runtimeInputs, and sudo resets
        # PATH again, so both binaries are addressed by absolute path.
        sudo_bin=/run/wrappers/bin/sudo
        ssh_to_age=${pkgs.ssh-to-age}/bin/ssh-to-age

        tmp="$(mktemp)"
        chmod 600 "$tmp"
        trap 'rm -f "$tmp"' EXIT

        if [ -r "$host_key" ]; then
          "$ssh_to_age" -private-key -i "$host_key" > "$tmp"
        elif [ -x "$sudo_bin" ]; then
          echo "sops-edit: reading $host_key via sudo" >&2
          "$sudo_bin" "$ssh_to_age" -private-key -i "$host_key" > "$tmp"
        else
          echo "sops-edit: cannot read $host_key and $sudo_bin is missing" >&2
          exit 1
        fi

        # sops runs as the invoking user, so the file keeps its ownership.
        SOPS_AGE_KEY_FILE="$tmp" sops "$target"
      '';
    };

    # Re-encrypt the repo's secrets to the recipients listed in .sops.yaml (run
    # after adding one, e.g. gear5th's user key). Same identity handling as
    # sopsEdit: the SSH host key is converted in memory and shredded on exit.
    sopsUpdatekeys = pkgs.writeShellApplication {
      name = "sops-updatekeys";
      runtimeInputs = [pkgs.sops pkgs.coreutils];
      text = ''
        set -euo pipefail

        host_key=/etc/ssh/ssh_host_ed25519_key
        target="''${1:-secrets/secrets.yaml}"

        sudo_bin=/run/wrappers/bin/sudo
        ssh_to_age=${pkgs.ssh-to-age}/bin/ssh-to-age

        tmp="$(mktemp)"
        chmod 600 "$tmp"
        trap 'rm -f "$tmp"' EXIT

        if [ -r "$host_key" ]; then
          "$ssh_to_age" -private-key -i "$host_key" > "$tmp"
        elif [ -x "$sudo_bin" ]; then
          echo "sops-updatekeys: reading $host_key via sudo" >&2
          "$sudo_bin" "$ssh_to_age" -private-key -i "$host_key" > "$tmp"
        else
          echo "sops-updatekeys: cannot read $host_key and $sudo_bin is missing" >&2
          exit 1
        fi

        SOPS_AGE_KEY_FILE="$tmp" sops updatekeys "$target"
      '';
    };
  in {
    imports = [inputs.sops-nix.nixosModules.sops];

    sops.defaultSopsFile = ../../secrets/secrets.yaml;

    # Left at the default (root, 0400): only the rendered template below needs to
    # be readable by the desktop user.
    sops.secrets.opencode_api_key = {};
    sops.secrets.deepseek_api_key = {};

    # pi reads provider keys from the environment. This renders both into a
    # single file that zsh sources at shell startup. The variables must be
    # exported: sourcing alone would only set shell-local variables.
    sops.templates."pi-provider-keys.env" = {
      path = renderedEnv;
      content = ''
        export OPENCODE_API_KEY="${config.sops.placeholder.opencode_api_key}"
        export DEEPSEEK_API_KEY="${config.sops.placeholder.deepseek_api_key}"
      '';
      owner = "ejverat";
      group = "users";
      mode = "0400";
    };

    # sops for editing the repo's secrets, ssh-to-age for re-deriving recipients.
    environment.systemPackages = [pkgs.sops pkgs.ssh-to-age sopsEdit sopsUpdatekeys];
  };

  # Portable user layer (non-NixOS hosts, e.g. gear5th/Debian): there is no root
  # sops, so the same secrets are decrypted *as the user* with an age identity
  # derived from the user's SSH key (sops.age.sshKeyPaths — no separate age key to
  # generate or back up) and rendered into a user-owned file that the portable zsh
  # sources, mirroring chopper's /run/secrets path. The secrets file must list
  # that key's age recipient; re-encrypt with `sops updatekeys secrets/secrets.yaml`
  # (the nixosModule above ships the sops-updatekeys wrapper for that).
  flake.homeModules.secrets = {config, pkgs, ...}: {
    imports = [inputs.sops-nix.homeManagerModules.default];

    sops.age.sshKeyPaths = ["${config.home.homeDirectory}/.ssh/id_ed25519"];
    sops.defaultSopsFile = ../../secrets/secrets.yaml;

    sops.secrets.opencode_api_key = {};
    sops.secrets.deepseek_api_key = {};

    sops.templates."pi-provider-keys.env" = {
      path = "${config.home.homeDirectory}/.config/pi-provider-keys.env";
      content = ''
        export OPENCODE_API_KEY="${config.sops.placeholder.opencode_api_key}"
        export DEEPSEEK_API_KEY="${config.sops.placeholder.deepseek_api_key}"
      '';
      mode = "0400";
    };
  };
}
