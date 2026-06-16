---
description: Repo-wide conventions for this single-host NixOS homelab.
paths:
  - "**/*.nix"
---

# Conventions

Single-host NixOS homeserver. Full design in `docs/architecture.md`,
threat model + hardening in `docs/security.md`. Honor those.

## Structure

- **Flat, single host.** One inline `nixosConfigurations.homeserver` in
  `flake.nix`. No `mkNixosConfiguration`, no `common/`/`shared/`/`environments/`
  multi-machine layers — those existed only to share across machines (gone).
- One concern per file in `modules/`; one service per file in `services/`.
- `hardware/` (disko + kernel) is carried verbatim — disko generates the fstab,
  so it must stay. Don't hand-write `fileSystems` that disko owns.

## Locality of behaviour

system and home-manager config for one concern live in the **same file**.
home-manager runs as a NixOS module, so any file may set both system options and
`home-manager.users.<u>.*` — those merge across files. No monolithic `home.nix`.

## Users

- `homeserver` — human/login (SSH, samba), in group `media`.
- `srv` — non-login, runs all rootless containers (`linger` + `autoSubUidGidRange`).
- `media` group — shared; data under `/srv/data` is `srv:media` 2775 (setgid).

## Rootless vs native split

- **Rootless (srv)**: all app containers. See the adding-services rule.
- **Native/host**: nginx (80/443 + ACME + Cloudflare real-ip), adguard (53),
  wireguard (kernel), samba (445), smartd, sshd, webhook (root, for deploys).

## Images & updates

- `autoUpdate = "registry"` (podman-native) for internal/low-risk images.
- Pin **internet-facing** images by digest; update deliberately (supply chain).

## Workflow

- Always `nixos-rebuild build --flake .#homeserver` before committing — must pass.
- **Do NOT `switch` on the live host until parity** — this config tears down any
  service not yet migrated. Build-only is safe; cut over per-wave deliberately.
- Conventional-commit messages. Push to `git@github.com:tigorlazuardi/homelab`.
