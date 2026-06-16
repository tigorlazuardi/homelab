---
description: Storage tiering — which disk each kind of data lives on, and why.
paths:
  - "services/**"
  - "modules/users.nix"
---

# Storage tiering

Four physical mounts, each a deliberate tier. Put data on the right one.

| tier | mount | use for | notes |
|---|---|---|---|
| **state** (SSD) | `/var/mnt/state` | service config, db, search index, observability TSDB | fast, high R/W, treat space as scarce |
| **wolf** (HDD) | `/var/mnt/wolf` | durable-but-replaceable bulk: arr tv/movies, music, manga, youtube, **arr downloads** | big; re-downloadable if lost |
| **fenrir** (HDD) | `/var/mnt/fenrir` | sentimental / irreplaceable: immich photos, paperless documents | back this up; never disposable |
| **nas** (DYING HDD) | `/var/mnt/nas` | disposable downloads only (qbit-personal, jdownloader) | failing SMART; lose-nothing data only. Being phased out — do NOT put durable data here. |

## Rules

- **Config/db/index → state.** Per-app dir `/var/mnt/state/<app>`, created by the
  service's own `tmpfiles`. Even for apps whose *content* lives elsewhere
  (paperless index → state, docs → fenrir; immich db → state, photos → fenrir).
- **Bulk media → wolf.** Owned `srv:media` 2775 (setgid).
- **Irreplaceable → fenrir.** Only immich + paperless docs today.
- **Downloads:**
  - arr-managed → `/var/mnt/wolf/downloads`, mounted at the SAME container path
    the *arr stack sees (`/data/downloads`) so imports **hardlink** into
    `/data/media` on wolf (same filesystem). qBittorrent maps its arr categories
    there.
  - personal/manual (qbit default, jdownloader) → `/var/mnt/nas/downloads`.
- **Hardlink rule:** a downloader's target and the importer's library must be the
  same filesystem AND the same container path. That's why arr + qbit both see
  wolf as `/data`.
- Tier roots are owned in `modules/users.nix`; per-app subdirs in each service.
- Never write durable/sentimental data to nas — it's dying.
