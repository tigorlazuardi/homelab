#!/usr/bin/env bash
# Cutover ROOT SCRIPT 2 — post-switch ownership fix (run as root, AFTER switch).
# The switch created the `srv` user; migrated data is still owned by the old
# uid (homeserver/root). keep-id maps container app-uids -> srv, so the data must
# be owned by srv. Then restart srv's user manager so containers re-init clean.
set -uo pipefail

if ! id srv >/dev/null 2>&1; then
  echo "ERROR: srv user does not exist — run the switch (GATE B) first."; exit 1
fi
SRV=$(id -u srv)
echo "srv uid = $SRV"

echo "=== chown migrated data -> srv:media ==="
chown -R srv:media /var/mnt/wolf/media /var/mnt/wolf/torrents
for app in sonarr sonarr-anime radarr prowlarr bazarr qbittorrent recyclarr \
           jellyfin navidrome suwayomi ytptube jdownloader paperless immich; do
  [ -e "/var/mnt/state/$app" ] && chown -R srv:media "/var/mnt/state/$app" && echo "state/$app"
done
[ -e /var/mnt/fenrir/paperless ] && chown -R srv:media /var/mnt/fenrir/paperless && echo "fenrir/paperless"

echo "=== restart srv user manager (containers re-init with correct perms) ==="
systemctl restart "user@${SRV}.service"
sleep 5

echo "=== srv user units ==="
sudo -u srv XDG_RUNTIME_DIR=/run/user/$SRV systemctl --user list-units --type=service --no-pager 2>/dev/null | grep -E 'immich|sonarr|radarr|prowlarr|bazarr|qbittorrent|jellyfin|paperless|navidrome|grafana|prometheus|loki|tempo|tinyauth' | head -40
echo "=== DONE chown+restart. Proceed to verification checklist. ==="
