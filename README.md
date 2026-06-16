# homelab

Single-host NixOS homeserver — flake-based, rootless podman (quadlet), sops secrets.

```
                    Cloudflare
                        │
                  ┌─────▼─────┐   host (native, privileged)
   internet ─────▶│   nginx   │   adguard · wireguard · samba · smartd · sshd
                  └─────┬─────┘
                        │ proxy → 127.0.0.1:<port>
            ┌───────────▼───────────┐  rootless podman, user `srv`, userns=keep-id
            │  jellyfin  navidrome   │
            │  qbittorrent  *arr     │  data: /srv/data  (srv:media, 2775)
            │  immich  paperless ... │  observability: Alloy→Prom/Loki/Tempo→Grafana
            └────────────────────────┘
```

## Layout

| Path | What |
|------|------|
| `flake.nix` | inputs + `nixosConfigurations.homeserver` |
| `configuration.nix` | imports + Home Manager scaffold |
| `hardware/` | disko (fstab source) + kernel + mounts |
| `modules/` | one concern per file (system + home-manager co-located) |
| `services/` | one file per service |
| `secrets/` | sops-encrypted (age) |
| `docs/` | [architecture](docs/architecture.md) · [security](docs/security.md) |

## Build / switch

```bash
nixos-rebuild build  --flake .#homeserver   # dry
sudo nixos-rebuild switch --flake .#homeserver
```

Secrets need `/opt/age-key.txt` (0400, root) on the host to decrypt at activation.

## Status

Greenfield rebuild in progress. **flaresolverr** is the migrated pilot proving the
rootless-quadlet pattern; remaining services migrate in waves (see architecture
doc). Not yet switched on the live host.

## License

MIT — see [LICENSE](LICENSE).
