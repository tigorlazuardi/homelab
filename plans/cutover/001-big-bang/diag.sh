#!/usr/bin/env bash
# Cutover diagnostic — dump state + logs for the not-yet-healthy srv services.
# Run as root: sudo bash diag.sh
SRV=$(id -u srv)
run() { sudo -u srv XDG_RUNTIME_DIR="/run/user/$SRV" "$@"; }

for u in immich-server immich-postgres immich-valkey jellyfin paperless-ngx paperless-redis qbittorrent tempo; do
  printf '\n========== %s = %s ==========\n' "$u" "$(run systemctl --user is-active "$u" 2>/dev/null)"
  run journalctl --user -u "$u" -n 12 --no-pager 2>/dev/null | tail -12
done

echo
echo "========== ownership spot-check =========="
ls -ld /var/mnt/state/immich/postgres /var/mnt/state/jellyfin/config \
       /var/mnt/state/paperless/data /var/mnt/state/qbittorrent \
       /var/mnt/fenrir/paperless/media 2>/dev/null
