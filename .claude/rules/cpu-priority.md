# CPU Priority

All user processes share a hard ceiling: `user.slice` CPUQuota=680% (85% of 8 threads).
Priority within that budget is enforced via cgroup v2 CPUWeight hierarchy — no
per-service quotas needed. Higher effective weight = more CPU when competing.

## Priority tiers

| Tier | Who | CPUWeight path | Effective share (saturated) |
|---|---|---|---|
| **Interactive** | jellyfin (active stream) | user-1001(150) × media-interactive(200) | ≈57% |
| **Coding** | zellij + claude sessions | user-1000(100) × sessions(100) | ≈40% |
| **Batch** | ytptube, immich (all containers) | user-1001(150) × media-batch(10), CPUQuota=240% | ≈3% (hard cap: 3 threads) |

**Interactive rule is absolute**: a service wins at full interactive priority ONLY
when the user is actively using it. When idle it holds zero budget and the lower
tiers expand freely. This is structural — cgroups naturally handle it (idle process
uses no CPU regardless of weight).

## Sluggishness tolerance per service

Background jobs are ranked by how much delay is acceptable to the user:

| Service | Tier | Tolerance | Reason |
|---|---|---|---|
| jellyfin transcode | interactive | **0%** — any buffering breaks UX | live playback |
| zellij + claude | coding | **~5%** — small lag is annoying but acceptable | LLM I/O waits hide it |
| immich server (ffmpeg/thumbs) | batch | **70%** — import can take hours anyway | bulk async |
| immich machine learning | batch | **85%** — face/CLIP runs when idle | fully background |
| ytptube (yt-dlp + ffmpeg) | batch | **90%** — download finishes eventually | async queue |
| immich postgres/valkey | batch | **60%** — db slowdown delays import, not UX | support role |

Tolerance = how slow it can go before the user notices or cares. Lower = more
sensitive; treat like interactive if tolerance < 20%.

## Assigning new services

1. **Interactive UI / live playback** → `Slice = "media-interactive.slice"`, srv user
2. **Coding / human-facing tool** → `Slice = "sessions.slice"`, homeserver user
3. **Batch import / download / inference** → `Slice = "media-batch.slice"`, srv user
4. **Mixed** (interactive UI + heavy background) → split: interactive slice for the
   front-end process, batch slice for worker/import processes. Or assign to the tier
   that matches the DOMINANT user-facing pattern.

Never add a new per-service `CPUQuota` — the global user.slice ceiling already
caps total usage. Only use `CPUWeight` within the slice to control relative priority.

## Implementation files

- `modules/cpu-budget.nix` — system-level user.slice quota + user-N.slice weights
- `services/media-slice.nix` — srv user: media-interactive.slice + media-batch.slice
- `modules/home/claude-sessions.nix` — homeserver user: sessions.slice weight
- `services/jellyfin.nix` — interactive tier (media-interactive.slice)
- `services/ytptube.nix`, `services/immich.nix` — batch tier (media-batch.slice)

## Live-apply commands (no service restart)

Apply system-level weights/quota immediately:
```bash
# Global ceiling (takes effect immediately)
sudo systemctl set-property user.slice CPUQuota=680%

# User-level weights (homeserver vs srv split)
sudo systemctl set-property user-1000.slice CPUWeight=100
sudo systemctl set-property user-1001.slice CPUWeight=150

# sessions.slice: remove old quota, set weight (run as homeserver user)
systemctl --user set-property sessions.slice CPUQuota=
systemctl --user set-property sessions.slice CPUWeight=100

# Create + configure the new srv user slices (as srv user or via sudo -u srv)
sudo -u srv XDG_RUNTIME_DIR=/run/user/1001 systemctl --user start media-interactive.slice
sudo -u srv XDG_RUNTIME_DIR=/run/user/1001 systemctl --user set-property media-interactive.slice CPUWeight=200
sudo -u srv XDG_RUNTIME_DIR=/run/user/1001 systemctl --user start media-batch.slice
sudo -u srv XDG_RUNTIME_DIR=/run/user/1001 systemctl --user set-property media-batch.slice CPUWeight=10
```

Services (jellyfin, ytptube, immich) must restart to pick up new Slice= values —
that happens automatically on `nixos-rebuild switch` and does NOT affect zellij
sessions (those unit files are unchanged; slice changes don't restart child units).
