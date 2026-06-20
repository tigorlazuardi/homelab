#!/usr/bin/env bash
# Build the plan container image into the srv rootless podman store.
# Run this BEFORE nixos-rebuild switch — the quadlet unit won't start without the image.
set -euo pipefail

# srv (uid 1001) cannot read homeserver's home, so the build context can't live
# under /home/homeserver. Stage the Containerfile in a world-readable temp dir.
src="$(cd "$(dirname "$0")/../containers/plan" && pwd)"
ctx="$(mktemp -d /tmp/plan-build.XXXXXX)"
chmod 755 "$ctx"
cp "$src/Containerfile" "$ctx/"

# cd into a srv-readable dir first — sudo inherits cwd, and srv can't chdir into
# homeserver's home (Permission denied before podman even runs).
cd "$ctx"
/run/wrappers/bin/sudo -u srv XDG_RUNTIME_DIR=/run/user/1001 podman build -t localhost/plan:latest "$ctx"

cd /tmp && rm -rf "$ctx"
