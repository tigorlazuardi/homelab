#!/usr/bin/env bash
# Merge the OLD personal qbit metadata (292 torrents + tags + RSS + categories)
# into the single qbit. The single qbit's BT_backup is empty (carried arr config;
# arr re-adds its own torrents), so this is an additive copy — no conflict. Blobs
# stay on nas (/downloads = nas/torrents/downloads); only metadata moves to the
# SSD config. Leaves qBittorrent.conf alone (keeps the working WebUI); enable RSS
# auto-download in the UI afterwards (feeds + rules are copied). Run as root.
set -uo pipefail
cd /tmp
SRV=$(id -u srv)
u() { sudo -u srv XDG_RUNTIME_DIR="/run/user/$SRV" "$@"; }
QB=/var/mnt/state/qbittorrent/qBittorrent
OLD=/var/mnt/nas/torrents/config/qBittorrent

u systemctl --user stop qbittorrent 2>/dev/null

ts=$(date +%s 2>/dev/null || echo bak)
cp -a /var/mnt/state/qbittorrent "/var/mnt/state/qbittorrent.bak.$ts"
echo "backed up config -> state/qbittorrent.bak.$ts"

cp -an "$OLD/BT_backup/." "$QB/BT_backup/"            # 292 torrents + per-torrent tags
mkdir -p "$QB/rss"; cp -a "$OLD/rss/." "$QB/rss/"     # RSS feeds + download rules
cp -a "$OLD/categories.json" "$QB/categories.json"    # category defs (arr re-creates its own)
[ -f "$OLD/watched_folders.json" ] && cp -a "$OLD/watched_folders.json" "$QB/watched_folders.json"

chown -R srv:media /var/mnt/state/qbittorrent
echo "merged. BT_backup now: $(ls "$QB"/BT_backup/*.fastresume 2>/dev/null | wc -l) torrents"

u systemctl --user restart qbittorrent
sleep 12
echo "== qbit = $(u systemctl --user is-active qbittorrent) =="
curl -s -o /dev/null -w 'qbit :8083 -> %{http_code}\n' --max-time 8 http://127.0.0.1:8083/ 2>/dev/null
