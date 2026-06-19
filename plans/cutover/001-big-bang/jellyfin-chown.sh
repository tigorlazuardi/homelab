#!/usr/bin/env bash
# Under the default rootless userns, jellyfin runs as a mapped subuid (container
# uid 1000 = abc), but the config tree is owned by srv (container root) → EACCES.
# Fix ownership FROM INSIDE srv's userns with `podman unshare chown` so container
# uid 1000 maps to the correct host subuid automatically. Restore the carried
# config first (so it's preserved), then chown it to abc.
set -uo pipefail
SRV=$(id -u srv)
u() { sudo -u srv XDG_RUNTIME_DIR="/run/user/$SRV" "$@"; }
J=/var/mnt/state/jellyfin

u systemctl --user stop jellyfin 2>/dev/null
u systemctl --user reset-failed jellyfin 2>/dev/null

# restore the most recent backup over the empty dirs
cb=$(ls -d "$J"/config.bak.* 2>/dev/null | tail -1)
kb=$(ls -d "$J"/cache.bak.*  2>/dev/null | tail -1)
if [ -n "$cb" ]; then rm -rf "$J/config"; mv "$cb" "$J/config"; echo "restored $cb -> config"; fi
if [ -n "$kb" ]; then rm -rf "$J/cache";  mv "$kb" "$J/cache";  echo "restored $kb -> cache"; fi

# chown to container uid/gid 1000 (abc) within srv's userns
u podman unshare chown -R 1000:1000 "$J/config" "$J/cache"
echo "chowned config+cache to abc (subuid) via podman unshare"

u systemctl --user restart jellyfin
sleep 25
echo "== state = $(u systemctl --user is-active jellyfin) =="
u journalctl --user -u jellyfin -n 15 --no-pager | tail -15
curl -s -o /dev/null -w 'jellyfin :8096 -> %{http_code}\n' --max-time 6 http://127.0.0.1:8096/ 2>/dev/null
