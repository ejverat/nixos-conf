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
}: let
  # Shared provider-keys paths and the sops wrapper generator. See
  # modules/lib/_paths.nix and modules/lib/_sops-wrapper.nix.
  paths = import ../lib/_paths.nix;
  mkSopsWrapper = import ../lib/_sops-wrapper.nix;
in {
  flake.nixosModules.secrets = {
    config,
    pkgs,
    lib,
    ...
  }: let
    # Path of the rendered env file. modules/features/zsh.nix sources this exact
    # path from the wrapper's zshenv; both come from modules/lib/_paths.nix.
    renderedEnv = paths.providerKeysEnvNixos;

    # Editing the encrypted file needs the age identity, which is the SSH host
    # key and is therefore root-only. This fragment converts it in memory into a
    # short-lived 0600 file so `sops` can decrypt, then shreds it on exit; the
    # key material never reaches the terminal or the shell history. The rest of
    # the wrapper is shared: modules/lib/_sops-wrapper.nix.
    nixosIdentity = name: ''
      host_key=/etc/ssh/ssh_host_ed25519_key

      # writeShellApplication restricts PATH to runtimeInputs, and sudo resets
      # PATH again, so the wrapper is addressed by absolute path.
      sudo_bin=/run/wrappers/bin/sudo

      if [ -r "$host_key" ]; then
        ssh-to-age -private-key -i "$host_key" > "$tmp"
      elif [ -x "$sudo_bin" ]; then
        echo "${name}: reading $host_key via sudo" >&2
        "$sudo_bin" ssh-to-age -private-key -i "$host_key" > "$tmp"
      else
        echo "${name}: cannot read $host_key and $sudo_bin is missing" >&2
        exit 1
      fi
    '';
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
      owner = config.nixosConf.user.name;
      group = "users";
      mode = "0400";
    };

    # sops for editing the repo's secrets, ssh-to-age for re-deriving recipients.
    environment.systemPackages = [
      pkgs.sops
      pkgs.ssh-to-age
      (mkSopsWrapper {
        inherit pkgs;
        name = "sops-edit";
        identity = nixosIdentity "sops-edit";
      })
      (mkSopsWrapper {
        inherit pkgs;
        name = "sops-updatekeys";
        identity = nixosIdentity "sops-updatekeys";
        extra = "updatekeys";
      })
    ];
  };

  # Portable user layer (non-NixOS hosts, e.g. gear5th/Debian): there is no root
  # sops, so the same secrets are decrypted *as the user* with an age identity
  # derived from the user's SSH key (sops.age.sshKeyPaths — no separate age key to
  # generate or back up) and rendered into a user-owned file that the portable zsh
  # sources, mirroring chopper's /run/secrets path. The secrets file must list
  # that key's age recipient; re-encrypt with `sops updatekeys secrets/secrets.yaml`
  # (the nixosModule above ships the sops-updatekeys wrapper for that).
  flake.homeModules.secrets = {config, pkgs, ...}: let
    # Same convenience as the NixOS module, but user-mode: the age identity is
    # the user's own SSH key, so there is no sudo and no host key involved. The
    # derived age key is materialized into a 0600 temp file and shredded on exit;
    # it is deliberately NOT persisted to ~/.config/sops/age/keys.txt, because
    # that file would be an unprotected copy of a key derived from the SSH one.
    # The rest of the wrapper is shared: modules/lib/_sops-wrapper.nix.
    portableIdentity = name: ''
      ssh_key="''${SOPS_EDIT_SSH_KEY:-$HOME/.ssh/id_ed25519}"

      if [ ! -r "$ssh_key" ]; then
        echo "${name}: cannot read $ssh_key" >&2
        exit 1
      fi

      # Fails on a passphrase-protected key: ssh-to-age cannot prompt here.
      ssh-to-age -private-key -i "$ssh_key" > "$tmp"
    '';
  in {
    imports = [inputs.sops-nix.homeManagerModules.default];

    # `sops-edit` opens the decrypted file in $EDITOR and re-encrypts it on save
    # (to every recipient listed in .sops.yaml, so chopper keeps its access).
    # `sops-updatekeys` re-wraps the data key after adding a recipient.
    home.packages = [
      (mkSopsWrapper {
        inherit pkgs;
        name = "sops-edit";
        identity = portableIdentity "sops-edit";
      })
      (mkSopsWrapper {
        inherit pkgs;
        name = "sops-updatekeys";
        identity = portableIdentity "sops-updatekeys";
        extra = "updatekeys";
      })
    ];

    sops.age.sshKeyPaths = ["${config.home.homeDirectory}/.ssh/id_ed25519"];
    sops.defaultSopsFile = ../../secrets/secrets.yaml;

    sops.secrets.opencode_api_key = {};
    sops.secrets.deepseek_api_key = {};

    sops.templates."pi-provider-keys.env" = {
      path = "${config.home.homeDirectory}/${paths.providerKeysEnvPortable}";
      content = ''
        export OPENCODE_API_KEY="${config.sops.placeholder.opencode_api_key}"
        export DEEPSEEK_API_KEY="${config.sops.placeholder.deepseek_api_key}"
      '';
      mode = "0400";
    };
  };
}
