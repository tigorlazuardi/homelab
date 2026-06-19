#!/usr/bin/env bash
# Switch to official jellyfin image + restart, then show status. Run as root.
set -uo pipefail
SRV=$(id -u srv)
u() { sudo -u srv XDG_RUNTIME_DIR="/run/user/$SRV" "$@"; }

echo "== switch =="; nixos-rebuild switch --flake /home/homeserver/homelab#homeserver 2>&1 | tail -4
echo "== restart jellyfin (pulls official image, may take a bit) =="
u systemctl --user reset-failed jellyfin 2>/dev/null
u systemctl --user restart jellyfin
sleep 25
echo "== state = $(u systemctl --user is-active jellyfin) =="
u journalctl --user -u jellyfin -n 18 --no-pager | tail -18
echo "== http probe =="; curl -s -o /dev/null -w 'jellyfin :8096 -> %{http_code}\n' --max-time 6 http://127.0.0.1:8096/ 2>/dev/null
