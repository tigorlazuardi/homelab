#!/usr/bin/env bash
# Switch (suwayomi nested-mount fix) + fix jellyfin ownership (userns=null →
# config must be owned by the mapped subuid; chown via podman unshare). Run as root.
set -uo pipefail
SRV=$(id -u srv)
u() { sudo -u srv XDG_RUNTIME_DIR="/run/user/$SRV" "$@"; }
J=/var/mnt/state/jellyfin

echo "== switch =="; nixos-rebuild switch --flake /home/homeserver/homelab#homeserver 2>&1 | tail -4

echo "== suwayomi restart =="
u systemctl --user reset-failed suwayomi 2>/dev/null
u systemctl --user restart suwayomi

echo "== jellyfin: restore carried config + chown to abc (subuid) =="
u systemctl --user stop jellyfin 2>/dev/null
u systemctl --user reset-failed jellyfin 2>/dev/null
cb=$(ls -d "$J"/config.bak.* 2>/dev/null | tail -1)
kb=$(ls -d "$J"/cache.bak.*  2>/dev/null | tail -1)
if [ -n "${cb:-}" ]; then rm -rf "$J/config"; mv "$cb" "$J/config"; echo "restored config"; fi
if [ -n "${kb:-}" ]; then rm -rf "$J/cache";  mv "$kb" "$J/cache";  echo "restored cache"; fi
u podman unshare chown -R 1000:1000 "$J/config" "$J/cache"
u systemctl --user restart jellyfin

sleep 25
for s in suwayomi jellyfin; do
  printf '\n== %s = %s ==\n' "$s" "$(u systemctl --user is-active $s)"
done
echo "== probes =="
for p in 4567:suwayomi 8096:jellyfin; do port=${p%%:*}; n=${p##*:}; printf '%-9s :%-5s -> %s\n' "$n" "$port" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 http://127.0.0.1:$port/ 2>/dev/null)"; done
