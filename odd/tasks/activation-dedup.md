# Feature: deduplicate the NixOS/home-manager activations

## Goal

The portable features carry two implementations (NixOS module + home module)
and, for the pi ecosystem and sops, the shell bodies were duplicated almost
verbatim. Extract the shared bodies into `modules/lib/` so each variant only
keeps what genuinely differs (ownership on NixOS, the activation dependency).

## Decisions

- **`modules/lib/_pi-activation.nix`**: the `~/.pi/agent/settings.json`
  bootstrap plus the additive merge. Callers pass `owner` (NixOS: `user:users`
  to chown the created paths; home-manager: omitted). Used by `gentle-pi.nix`
  and `engram.nix`, both variants.
- **`modules/lib/_gentle-profile.nix`**: seed + link the vendored
  `gentle-profile` script. Same `owner` parameter. Used by `gentle-pi.nix`.
- **`modules/lib/_sops-wrapper.nix`**: the sops wrapper generator. The only
  per-host difference is how the age identity is obtained, injected as an
  `identity` shell fragment (NixOS: root SSH host key with a sudo fallback;
  standalone: the user's own SSH key). Used by `secrets.nix`, both variants.
- All three live under `modules/lib/` with a leading underscore, so import-tree
  skips them.
- The shared bodies were written to reproduce the previous shell text closely;
  the one intentional normalization is that the NixOS chowns now run right after
  each creation via the `owner` parameter instead of being spelled out inline.

## Tasks

1. Add `_pi-activation.nix`; refactor `gentle-pi.nix` and `engram.nix`.
2. Add `_gentle-profile.nix`; refactor `gentle-pi.nix`.
3. Add `_sops-wrapper.nix`; refactor `secrets.nix`.

## Verification evidence

The generated scripts were inspected, not just evaluated:

- chopper `activate`: `gentleProfileLink`, `piEngram` and `piGentlePi` snippets
  reproduce the previous text (same chowns: `chown ejverat:users "$src"`,
  `chown -h … "$dst"`, `chown -R ejverat:users "/home/ejverat/.pi"`,
  `chown ejverat:users "$settings"`).
- gear5th `activate`: same sections without chowns, merge intact.
- chopper `sops-edit`: host-key identity with the sudo fallback, `sops "$target"`.
- gear5th `sops-edit`: user-key identity, `sops "$target"`.
- `nix build` of both host configurations -> exit 0.
- `nix flake check --no-build` -> all checks passed.
- drv paths change (the wrapper scripts and activation text are regenerated);
  equivalence was verified by reading the generated scripts, since the
  activation itself cannot be exercised without switching.

## Commit identities

- [ ] `refactor: deduplicate the gentle-profile and pi-settings activations`
- [ ] `refactor: deduplicate the sops wrappers`
