{
  self,
  ...
}: {
  # Eval checks for both hosts. `nix flake check` builds these derivations, and
  # the runCommand interpolates only the drv path, so each configuration is
  # deeply evaluated but nothing is compiled. This closes the class of failure
  # where a shared home module breaks the other host's evaluation, which
  # `flake check` alone does not catch: it only reports `homeConfigurations`
  # shallowly.
  #
  # unsafeDiscardStringContext is required: a bare `${drvPath}` carries string
  # context, which would make the check depend on the whole system and turn
  # `nix flake check` into a full system build. Discarding it keeps the eval
  # (the string is still computed, so the config is forced) without the build
  # dependency.
  perSystem = {pkgs, ...}: {
    checks.chopper-eval = pkgs.runCommand "check-chopper-eval" {} ''
      echo "${builtins.unsafeDiscardStringContext self.nixosConfigurations.chopper.config.system.build.toplevel.drvPath}" > $out
    '';
    checks.gear5th-eval = pkgs.runCommand "check-gear5th-eval" {} ''
      echo "${builtins.unsafeDiscardStringContext self.homeConfigurations.gear5th.activationPackage.drvPath}" > $out
    '';
  };
}
