#!/usr/bin/env bash
# Cutover recovery — apply jellyfin keep-groups fix (switch) + restart the
# services that crash-looped during the GATE-C restart storm, then dump logs.
# Run as root: sudo bash recover.sh
set -uo pipefail
SRV=$(id -u srv)
u() { sudo -u srv XDG_RUNTIME_DIR="/run/user/$SRV" "$@"; }

echo "========== nixos-rebuild switch (jellyfin keep-groups) =========="
nixos-rebuild switch --flake /home/homeserver/homelab#homeserver 2>&1 | tail -5

echo "========== reset-failed + restart crash-looped units =========="
for s in dex tempo paperless-ngx jellyfin; do
  u systemctl --user reset-failed "$s" 2>/dev/null
  u systemctl --user restart "$s" 2>/dev/null && echo "restarted $s"
done
sleep 12

echo "========== states + logs =========="
for s in dex tempo paperless-ngx jellyfin; do
  printf '\n##### %s = %s #####\n' "$s" "$(u systemctl --user is-active "$s" 2>/dev/null)"
  u journalctl --user -u "$s" -n 14 --no-pager 2>/dev/null | tail -14
done
