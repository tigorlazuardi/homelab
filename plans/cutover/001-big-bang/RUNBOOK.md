# Cutover runbook — old rootful (dotfiles, 26.05) → new rootless homelab

Big-bang switch of the live homeserver from the old rootful `oci-containers`
config (`~/dotfiles`, NixOS 26.05) to the new rootless quadlet `homelab` config.
Plus migrating ~885G of media off the **dying nas disk** onto wolf.

**Decisions (locked):**
- Carry all arr/qbit configs forward; **add a 2nd sonarr instance** (`sonarr-anime`).
- `rsync -aH` the media **now** (non-destructive, old still running); switch later.
- Operator runs step-by-step; **gate every irreversible step** (switch, delete-from-nas).

## Ground truth (surveyed 2026-06-16)

| tier | mount | dev | size / used / avail |
|---|---|---|---|
| state | `/var/mnt/state` | nvme1n1p1 btrfs | 477G / 7.9G / 467G |
| wolf | `/var/mnt/wolf` | sdc1 ext4 | 3.6T / 1.6T / 1.8T |
| nas (DYING) | `/var/mnt/nas` | sda1 ext4 | 3.6T / 2.3T / 1.1T |
| fenrir | `/var/mnt/fenrir` | sdb1 btrfs | 3.6T / 240G / 3.4T |

Live system still old: `/run/current-system` = 26.05. **No `srv` user yet** —
it is created by the switch. `homeserver` = uid 1000. `srv` will be allocated
the next free uid at switch (record it: `id srv`).

### Old data locations (what carries)

| service | old path | new path | move |
|---|---|---|---|
| **arr media** | `nas/mediaserver/servarr/data/media/{anime,movies,tv}` (759G) | `wolf/media/{anime,movies,tv}` | **rsync nas→wolf** |
| **arr torrents** | `nas/mediaserver/servarr/data/torrents` (126G) | `wolf/torrents` | **rsync nas→wolf (same pass, hardlinks!)** |
| sonarr | `nas/.../servarr/sonarr` (118M) | `state/sonarr` | copy + chown |
| sonarr-anime | `nas/.../servarr/sonarr-anime` (100M) | `state/sonarr-anime` | copy + chown |
| radarr | `nas/.../servarr/radarr` (50M) | `state/radarr` | copy + chown |
| prowlarr | `nas/.../servarr/prowlarr` (88M) | `state/prowlarr` | copy + chown |
| bazarr | `nas/.../servarr/bazarr` (6.7M) | `state/bazarr` | copy + chown |
| qbittorrent | `nas/.../servarr/qbittorrent` (7.3M) | `state/qbittorrent` | copy + chown |
| navidrome | `state/navidrome` (98M) | `state/navidrome` | in-place chown |
| suwayomi | `state/suwayomi` (146M) + `wolf/suwayomi` (42G manga) | `state/suwayomi` + `wolf/media/manga` | chown + rename |
| ytptube | `state/ytptube` (48M) + `wolf/mediaserver/ytptube` (1.2T) | `state/ytptube` + `wolf/media/youtube` | chown + **rename (same fs, instant)** |
| searxng | `state/searxng` (152K) | `state/searxng/{config,data,valkey}` | restructure + chown |
| jdownloader | `state/jdownloader` (115M) | `state/jdownloader` | chown |
| paperless | `wolf/paperless-ngx` (271M) | `state/paperless/*` + `fenrir/paperless/*` | copy + split + chown |
| immich | `fenrir/immich/server/library` (236G) | mounted `:ro` external lib; FRESH db | no move (see immich.nix) |
| music | `nas/Music` (3.1G) | `wolf/media/music` | rsync nas→wolf |
| manga (alt) | `nas/tachidesk` (26G) | fold into `wolf/media/manga` | operator decides overlap w/ wolf/suwayomi |

**Dropped (not in new config, leave on disk until reclaimed):** signoz, ntfy,
plane, erpnext, attic, jellyfin (offered, not added), kavita, polaris, photoprism,
huly, redmage, etc. `recyclarr` (78M) old arr quality-profile syncer — not ported;
re-add later if wanted.

**Stays on nas (personal/disposable, by design):** `nas/torrents` (916G, old
standalone qbit-personal), `nas/jdownloader`, misc archives. New qbit personal →
`nas/downloads`; jdownloader → `nas/downloads`.

### Hardlink invariant (critical)

`data/media` ↔ `data/torrents` are **hardlinked** (seeding files hardlinked into
the library). They MUST be copied in a **single `rsync -aH` pass** over the parent
`servarr/data/`, else hardlinks break → double space + seeding detaches from
library. After copy, rearrange by `mv` **within wolf** (same fs → inode-preserving,
hardlinks survive any rename).

To preserve seeding without editing qbit fastresume, new container paths MUST
match old absolute paths: arr `/data/media/*`, downloads `/data/torrents`. Phase 0
renames the new `downloads` dir → `torrents` so carried configs need **zero UI
path edits**.

---

## Phase 0 — config alignment (non-destructive, DONE in repo)

- [x] Add `sonarr-anime` instance (port 8990, `state/sonarr-anime`).
- [x] Rename download dir `wolf/downloads`→`wolf/torrents`, container path
      `/data/downloads`→`/data/torrents` (matches old → carried configs untouched).
- [x] Add `wolf/media/anime` tmpfiles.
- [x] Build + commit.

## Phase 1 — bulk media copy (non-destructive, old STILL RUNNING)

Safe/reversible — only writes to wolf, never touches nas or live services.

```bash
# ONE rsync over the parent so media↔torrents hardlinks are preserved.
sudo rsync -aHAX --info=progress2 --no-inc-recursive \
  /var/mnt/nas/mediaserver/servarr/data/ /var/mnt/wolf/_arrstage/
# youtube is already on wolf — defer its in-place rename to switch day (instant).
# music:
sudo rsync -aHAX --info=progress2 /var/mnt/nas/Music/ /var/mnt/wolf/_musicstage/
```

Hours of IO. Re-runnable (incremental) for the switch-day delta.

## Phase 2 — THE SWITCH (⚠ irreversible — gate each step)

1. **Stop old rootful media writers** (freeze the source):
   `sudo systemctl stop podman-sonarr podman-radarr podman-prowlarr podman-bazarr podman-qbittorrent ...`
2. **Final delta rsync** (same commands as Phase 1 — now near-instant).
3. **Rearrange wolf into final layout** (same-fs mv, hardlink-safe):
   ```bash
   mv /var/mnt/wolf/_arrstage/media/anime  /var/mnt/wolf/media/anime
   mv /var/mnt/wolf/_arrstage/media/movies /var/mnt/wolf/media/movies
   mv /var/mnt/wolf/_arrstage/media/tv     /var/mnt/wolf/media/tv
   mv /var/mnt/wolf/_arrstage/torrents     /var/mnt/wolf/torrents
   mv /var/mnt/wolf/mediaserver/ytptube    /var/mnt/wolf/media/youtube   # 1.2T instant
   mv /var/mnt/wolf/_musicstage            /var/mnt/wolf/media/music
   ```
4. **Copy arr/qbit + other configs** into `state/<app>` (rsync from servarr/*).
5. **Split paperless**: data/consume/redis→`state/paperless/*`, media/export→`fenrir/paperless/*`.
6. `sudo nixos-rebuild switch --flake ~/homelab#homeserver`  ← creates `srv`, starts rootless.
7. **chown migrated data to srv** (record `SRV=$(id -u srv)`):
   `sudo chown -R srv:media /var/mnt/wolf/media /var/mnt/wolf/torrents /var/mnt/state/{sonarr,sonarr-anime,radarr,prowlarr,bazarr,qbittorrent,navidrome,suwayomi,ytptube,jdownloader} ...`
8. **Verify** (Phase 4 checklist).

## Phase 3 — cleanup (⚠ irreversible — gate)

Only after Phase 4 fully green: reclaim nas.
`sudo rm -rf /var/mnt/nas/mediaserver/servarr/data` etc. Keep old immich db +
old configs until immich external-lib import verified.

## Phase 4 — verification checklist (runtime, post-switch)

- [ ] `id srv` recorded; `loginctl show-user srv` lingering.
- [ ] `sudo -u srv systemctl --user list-units 'immich*' '*arr*' ...` all active.
- [ ] keep-id ownership: container-written files land `srv:*` on host (not subuid).
- [ ] sops secrets readable by srv (`/run/secrets/*` owner srv).
- [ ] `host.containers.internal` reachable across stacks (prowlarr→flaresolverr:8191).
- [ ] qbit seeding resumed (torrents rechecked OK, paths `/data/torrents`).
- [ ] sonarr/radarr see library `/data/media/*`; import hardlinks (not copies).
- [ ] bazarr finds media beside it.
- [ ] immich: add External Library `/mnt/external/old`, scan, thumbs generate.
- [ ] grafana/alloy/prometheus/loki/tempo up; metrics+logs flowing.
- [ ] **infisical DB host**: old encrypted env still points at OLD ip — needs
      `sops secrets/infisical.env` edit (EXPLICIT user permission required).
- [ ] adguard, wireguard, samba, navidrome, suwayomi, ytptube, paperless reachable.

## Open items needing operator input at switch time

- `nas/tachidesk` (26G) vs `wolf/suwayomi` (42G) manga overlap — which is canonical?
- `recyclarr` re-add? (not ported)
- jellyfin re-add? (old config had it; new does not)
- infisical DB host edit (encrypted secret — needs explicit permission).
