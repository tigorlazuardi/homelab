# Architecture

Single-host NixOS homeserver. No multi-machine abstraction — read top to bottom.

## Why NixOS (and not Fedora/CoreOS + chezmoi)

Declarative whole-system state visibility is the deciding factor: the source *is*
the system. chezmoi manages dotfiles, not packages/services/state; CoreOS gives
atomic rollback but not declarative service config. One box → the multi-machine
sync benefit is gone, but the reproducibility + rollback value remains.

## Repo layout

```
flake.nix            # inputs + ONE inline nixosConfigurations.homeserver
configuration.nix    # imports + Home Manager scaffold + stateVersion
hardware/            # disko (generates fstab) + kernel + mounts — carried verbatim
modules/             # one concern per file; may co-locate system + home-manager
services/            # one file per service
secrets/             # sops-encrypted only
docs/
```

No `mkNixosConfiguration`, no `common/`/`shared/`/`environments/` — those existed
only to share across machines.

## Locality of behaviour (system + home-manager in one file)

home-manager runs as a NixOS module, so any concern file can write both system
options and `home-manager.users.<u>.*`. That option merges across all modules, so
each file contributes its own slice — no monolithic `home.nix`.

## User & data model

- `homeserver` — human/login user (SSH, samba), member of `media`.
- `srv` — dedicated non-login user, runs ALL rootless app containers
  (`linger` + `autoSubUidGidRange`).
- `media` group — both users; shared data is group-writable.

Data tree `/srv/data` owned `srv:media`, mode `2775` (setgid → new files inherit
`media`). Rootless containers use `userns=keep-id` so files land owned by `srv` on
disk — no subuid sprawl, no permission friction. Keep `downloads/` + `media/` on
one filesystem for atomic move / hardlink.

```
/srv/data/downloads     writers (qbittorrent, *arr)  :rw
/srv/data/media/{movies,tv,music}   readers (jellyfin, navidrome)  :ro
/srv/data/state         per-app config/db
```

## Containers — rootless quadlet (quadlet-nix)

Defined under `home-manager.users.srv.virtualisation.quadlet.containers.*`.
Each: `userns=keep-id`, loopback `publishPorts`, hardening (cap-drop all,
no-new-privileges), `autoUpdate="registry"` (podman-native auto-update via the
per-user `podman-auto-update.timer`).

Edge services stay **host/native** (privileged / kernel): nginx (80/443),
adguard (53), wireguard (NET_ADMIN), samba (445), smartd, openssh.

## Reverse proxy

nginx stays host (TLS terminator + fan-in). Strategy progression:
- **A (now):** each rootless service publishes `127.0.0.1:<port>`; nginx
  `proxyPass` → loopback. Simple, per-service host port.
- **C (end-state):** once all services rootless, optionally move nginx into the
  shared rootless network → reaches containers by name, drop the port registry.

## Networking

systemd-networkd, static `192.168.100.5/24`, gw `.1`, DNS `.5` (AdGuard). No
DHCP (stationary box; DHCP only added a route-flap failure mode).

## Observability — Grafana stack via Alloy OTLP gateway

`Alloy + Prometheus + Loki + Tempo + Grafana` (no Mimir — Prometheus is enough on
one node). Apps emit OTLP to **one endpoint (Alloy)**; Alloy fans out:

```
apps ──OTLP──▶ Alloy ──▶ metrics ─remote_write─▶ Prometheus
                  ├────▶ logs ──────────────────▶ Loki
                  └────▶ traces ────────────────▶ Tempo
host metrics: Alloy reads host /proc directly
```

Prometheus needs `--web.enable-remote-write-receiver`. OTel metrics: cumulative
temporality (SDK default, or `deltatocumulative` in Alloy). Grafana unified
alerting → Telegram. Replaces SigNoz + the host otel-collector.

## Notifications

Telegram only (ntfy + apprise dropped). smartd → Telegram direct; Grafana →
native Telegram contact point. Bot token/chat-id in sops, reused.

## Service inventory

**Host/native:** nginx, adguardhome, wireguard, openssh, samba, smartd.

**Observability (new):** alloy, prometheus, loki, tempo, grafana.

**Rootless (srv):** jellyfin, navidrome, immich, suwayomi (media) · qbittorrent,
jdownloader, ytptube, prowlarr*, sonarr*, radarr*, bazarr* (downloads/arr) ·
paperless-ngx, infisical · searxng, flaresolverr, webhook, wallrus.
(`*` = new additions.)

**Dropped:** signoz, host otel-collector, ntfy, apprise, vscode-server, plane,
attic, sukhoi-booth9, erpnext, all environments, nexus/envy.

**Immich:** re-enable with a FRESH Postgres; mount old originals as an External
Library `:ro` (albums/metadata lost — accepted; photos recovered, originals
untouched).

## Migration order

1. **flaresolverr** — pilot (done in repo). Proves the whole pattern.
2. stateless: searxng, suwayomi, ytptube, jdownloader.
3. stateful single: navidrome, qbittorrent, wallrus, paperless, infisical.
4. new builds: *arr stack, observability (Grafana), immich (fresh DB).
5. multi-container / critical last: nginx auto-vhost, adguard, samba.
