#!/usr/bin/env bash
# Own jellyfin config/cache by the host subuid that container uid 1000 (abc) maps
# to under the default rootless userns: subuid_base + (1000-1). Plain root chown
# (podman unshare was failing on cwd). Then restart. Run as root.
set -uo pipefail
SRV=$(id -u srv)
u() { sudo -u srv XDG_RUNTIME_DIR="/run/user/$SRV" "$@"; }
J=/var/mnt/state/jellyfin

ubase=$(grep '^srv:' /etc/subuid | cut -d: -f2)
gbase=$(grep '^srv:' /etc/subgid | cut -d: -f2)
uid=$((ubase + 999)); gid=$((gbase + 999))
echo "abc(1000) -> host $uid:$gid"
chown -R "$uid:$gid" "$J/config" "$J/cache"

u systemctl --user reset-failed jellyfin 2>/dev/null
u systemctl --user restart jellyfin
sleep 25
echo "== jellyfin = $(u systemctl --user is-active jellyfin) =="
curl -s -o /dev/null -w 'jellyfin :8096 -> %{http_code}\n' --max-time 8 http://127.0.0.1:8096/ 2>/dev/null
