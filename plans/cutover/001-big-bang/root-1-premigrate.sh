#!/usr/bin/env bash
# Cutover ROOT SCRIPT 1 — pre-switch data migration (run as root, BEFORE switch).
# Idempotent-ish: skips dirs that already exist. Old writers must be stopped.
set -euo pipefail
SERVARR=/var/mnt/nas/mediaserver/servarr
PNG=/var/mnt/wolf/paperless-ngx

say() { printf '\n=== %s ===\n' "$1"; }

say "manga: wolf/suwayomi/downloads -> wolf/media/manga"
if [ -d /var/mnt/wolf/suwayomi/downloads ] && [ ! -e /var/mnt/wolf/media/manga ]; then
  mv /var/mnt/wolf/suwayomi/downloads /var/mnt/wolf/media/manga
  echo "moved"; else echo "skip (already done / source gone)"; fi

say "arr/qbit/recyclarr configs -> /var/mnt/state/<app>"
for app in sonarr sonarr-anime radarr prowlarr bazarr qbittorrent recyclarr; do
  if [ -d "$SERVARR/$app" ] && [ ! -e "/var/mnt/state/$app" ]; then
    cp -a "$SERVARR/$app" "/var/mnt/state/$app"; echo "copied $app"
  else echo "skip $app"; fi
done

say "paperless split: config/db -> state, docs -> fenrir"
mkdir -p /var/mnt/state/paperless /var/mnt/fenrir/paperless
# data/consume/redis -> state (rebuildable, fast)
for d in data consume redis; do
  if [ -d "$PNG/$d" ] && [ ! -e "/var/mnt/state/paperless/$d" ]; then
    cp -a "$PNG/$d" "/var/mnt/state/paperless/$d"; echo "state/paperless/$d"
  else echo "skip state/paperless/$d"; fi
done
# media/export -> fenrir (sentimental)
for d in media export; do
  if [ -d "$PNG/$d" ] && [ ! -e "/var/mnt/fenrir/paperless/$d" ]; then
    cp -a "$PNG/$d" "/var/mnt/fenrir/paperless/$d"; echo "fenrir/paperless/$d"
  else echo "skip fenrir/paperless/$d"; fi
done

say "DONE pre-migrate. Verify below, then run the switch (GATE B)."
echo "state apps:"; ls /var/mnt/state | grep -E 'sonarr|radarr|prowlarr|bazarr|qbittorrent|recyclarr|paperless'
echo "wolf/media:"; ls /var/mnt/wolf/media
echo "fenrir/paperless:"; ls /var/mnt/fenrir/paperless 2>/dev/null
