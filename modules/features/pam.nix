{ ... }: {
  perSystem = { pkgs, ... }: {
    # nixpkgs' pam_unix.so is compiled to exec /run/wrappers/bin/unix_chkpwd,
    # which is the setuid wrapper NixOS creates (security.wrappers). On a
    # non-NixOS host that path is missing, so any user process authenticating
    # through PAM -- e.g. the noctalia/quickshell lock screen via
    # Quickshell.Services.Pam -- always rejects the password.
    #
    # This output gives scripts/fix-pam-unix-chkpwd.sh a deterministic handle on
    # the matching helper binary (same pin as the pam_unix that will run it).
    packages.linuxPam = pkgs.pam;
  };
}