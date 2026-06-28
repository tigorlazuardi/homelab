---
name: nixos-rebuild-flake-ref
description: Use whenever emitting, recommending, or running a `nixos-rebuild` command (build / switch / boot / test / dry-build) for this homelab. Never use the bare `.#homeserver` flake ref — it is cwd-dependent and ambiguous (breaks if the user pastes it from another dir). Always give an explicit path-anchored ref like `~/homelab#homeserver`, and resolve the real repo path on the host first instead of hardcoding it.
---

# nixos-rebuild flake reference

When handing the user a `nixos-rebuild` command, the flake ref must be
**unambiguous** — it should work no matter which directory the user pastes it
into.

## The rule

- **Never** emit the bare `.#homeserver`. The leading `.` means "flake in the
  current directory" — if the user isn't sitting in the repo, it fails or builds
  the wrong thing.
- **Always** anchor the path: `~/homelab#homeserver` (or an absolute
  `/home/homeserver/homelab#homeserver`).
- The attribute after `#` is the `nixosConfigurations` name — `homeserver` for
  this host (single inline config in `flake.nix`).

```fish
# good — unambiguous from anywhere
sudo nixos-rebuild switch --flake ~/homelab#homeserver
sudo nixos-rebuild build  --flake ~/homelab#homeserver   # build is fine without sudo

# bad — cwd-dependent
sudo nixos-rebuild switch --flake .#homeserver
```

## Don't hardcode — resolve the repo path

The repo currently lives at `/home/homeserver/homelab` (= `~/homelab` for the
`homeserver` user), but **look it up** rather than assuming, in case it moves or
the command runs for a different user. Quick resolve from inside the repo:

```fish
git rev-parse --show-toplevel        # → /home/homeserver/homelab
```

Use that result (or its `~`-relative form) as the flake path. When I'm already
operating inside the repo, I know the toplevel — emit that absolute/`~`-anchored
path, never `.#`.

## Note on `switch` vs `build`

`build` needs no root and is safe (validates nix + quadlet). `switch` needs root.
In this sandbox `sudo` is broken for the agent, so `switch` commands are handed to
the **user** to run — which is exactly when an unambiguous flake path matters most
(they paste it into their own shell, cwd unknown).
