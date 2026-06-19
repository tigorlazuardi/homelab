#!/usr/bin/env bash
# Fresh jellyfin config: the carried LSIO /config is owned by srv and jellyfin
# (running as a mapped subuid under the default rootless userns) can't write into
# the pre-populated tree. Back it up and start clean so LSIO chowns the empty
# /config to abc. You'll re-add libraries (point at /media/{tv,movies,anime,music}).
set -uo pipefail
SRV=$(id -u srv)
u() { sudo -u srv XDG_RUNTIME_DIR="/run/user/$SRV" "$@"; }
J=/var/mnt/state/jellyfin

u systemctl --user stop jellyfin 2>/dev/null
u systemctl --user reset-failed jellyfin 2>/dev/null

ts=$(date +%s 2>/dev/null || echo bak)
[ -d "$J/config" ] && mv "$J/config" "$J/config.bak.$ts" && echo "backed up config -> config.bak.$ts"
[ -d "$J/cache" ]  && mv "$J/cache"  "$J/cache.bak.$ts"  && echo "backed up cache -> cache.bak.$ts"
mkdir -p "$J/config" "$J/cache"
chown srv:media "$J/config" "$J/cache"
chmod 0750 "$J/config" "$J/cache"

u systemctl --user restart jellyfin
sleep 25
echo "== state = $(u systemctl --user is-active jellyfin) =="
u journalctl --user -u jellyfin -n 15 --no-pager | tail -15
curl -s -o /dev/null -w 'jellyfin :8096 -> %{http_code}\n' --max-time 6 http://127.0.0.1:8096/ 2>/dev/null
