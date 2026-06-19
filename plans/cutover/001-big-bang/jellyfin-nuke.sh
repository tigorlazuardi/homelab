#!/usr/bin/env bash
# Fresh jellyfin: wipe config/cache (+ all backups), recreate EMPTY dirs owned by
# the mapped subuid (chown of empty dirs always succeeds), let jellyfin build new.
# You re-add libraries: point at /media/{tv,movies,anime,music}. Run as root.
set -uo pipefail
cd /tmp
SRV=$(id -u srv)
u() { sudo -u srv XDG_RUNTIME_DIR="/run/user/$SRV" "$@"; }
J=/var/mnt/state/jellyfin

u systemctl --user stop jellyfin 2>/dev/null
u systemctl --user reset-failed jellyfin 2>/dev/null

rm -rf "$J"/config "$J"/cache "$J"/config.bak.* "$J"/cache.bak.*
mkdir -p "$J/config" "$J/cache"
chown srv:media "$J/config" "$J/cache"
chmod 0755 "$J/config" "$J/cache"
# hand the empty dirs to abc (container uid 1000) inside srv's userns
u podman unshare chown 1000:1000 "$J/config" "$J/cache"
echo "wiped + chowned empty config/cache to abc"

u systemctl --user restart jellyfin
sleep 25
echo "== jellyfin = $(u systemctl --user is-active jellyfin) =="
curl -s -o /dev/null -w 'jellyfin :8096 -> %{http_code}\n' --max-time 8 http://127.0.0.1:8096/ 2>/dev/null
