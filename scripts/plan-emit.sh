#!/usr/bin/env bash
# plan-emit.sh — publish a visual-plan/recap MDX into the local plan app dir.
#
# DOWN-TOLERANCE: writing the file is a plain filesystem write — it works even
# when plan.service (the container) is DOWN. The app renders it on next start.
# Only the write itself is a hard failure; the app probe is informational only.
#
# Usage: plan-emit.sh <slug> [mdx-file]
#        If mdx-file is omitted, MDX is read from stdin.

set -euo pipefail

PLAN_LOCAL_DIR_HOST="${PLAN_LOCAL_DIR_HOST:-/var/mnt/state/plan/plans}"

usage() {
    echo "Usage: $(basename "$0") <slug> [mdx-file]" >&2
    echo "  slug     lowercase alnum + hyphens only (e.g. my-feature-plan)" >&2
    echo "  mdx-file path to MDX file; omit to read from stdin" >&2
}

# --- arg validation ---

if [[ $# -lt 1 ]]; then
    echo "Error: <slug> is required." >&2
    usage
    exit 2
fi

SLUG="$1"
MDX_FILE="${2:-}"

# Safe slug: lowercase alnum and hyphens, no slashes, no dots, non-empty.
if [[ ! "$SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "Error: invalid slug '${SLUG}' — must be lowercase alnum + hyphens only, no slashes or dots." >&2
    usage
    exit 2
fi

# --- base dir check (only hard failure) ---

if [[ ! -d "$PLAN_LOCAL_DIR_HOST" ]]; then
    echo "Error: base dir '${PLAN_LOCAL_DIR_HOST}' does not exist." >&2
    echo "  The state mount may be missing or plan service not yet deployed." >&2
    echo "  Check: mountpoint /var/mnt/state && ls -la /var/mnt/state/plan/" >&2
    exit 1
fi

if [[ ! -w "$PLAN_LOCAL_DIR_HOST" ]]; then
    echo "Error: base dir '${PLAN_LOCAL_DIR_HOST}' is not writable by $(whoami) (uid=$(id -u))." >&2
    echo "  Expected: dir owned/group-writable by group 'media'; user must be in that group." >&2
    echo "  Check: ls -la /var/mnt/state/plan/ && id" >&2
    exit 1
fi

# --- prepare slug dir ---

SLUG_DIR="${PLAN_LOCAL_DIR_HOST}/${SLUG}"
mkdir -p "$SLUG_DIR"

# chmod 2770 so the app (group media) can mirror edits back via setgid.
# Tolerate failure if dir is owned by srv — the write is what matters.
if ! chmod 2770 "$SLUG_DIR" 2>/dev/null; then
    echo "Warning: could not chmod 2770 '${SLUG_DIR}' (likely owned by another user). Continuing — write may still succeed." >&2
fi

# --- atomic write ---

PLAN_MDX="${SLUG_DIR}/plan.mdx"
TMP_FILE=$(mktemp "${SLUG_DIR}/.plan.mdx.XXXXXX")

# Ensure tmp is cleaned up on unexpected exit before mv.
trap 'rm -f "$TMP_FILE"' EXIT

if [[ -n "$MDX_FILE" ]]; then
    cat "$MDX_FILE" > "$TMP_FILE"
else
    cat > "$TMP_FILE"
fi

chmod 664 "$TMP_FILE"
mv "$TMP_FILE" "$PLAN_MDX"

# mv succeeded — disarm the trap.
trap - EXIT

# --- probe app (informational only; never fails the script) ---

RENDER_URL="https://plan.tigor.web.id/local-plans/${SLUG}"

if curl -fsS -o /dev/null --max-time 3 http://127.0.0.1:3050/ 2>/dev/null; then
    echo "✓ written; render: ${RENDER_URL}"
else
    echo "✓ written to '${PLAN_MDX}'." >&2
    echo "Warning: plan app is down or unreachable on :3050. Plan is saved and will render once the app starts." >&2
    echo "  To start: sudo -u srv XDG_RUNTIME_DIR=/run/user/1001 systemctl --user start plan.service" >&2
    echo "  Render URL (once up): ${RENDER_URL}" >&2
fi

exit 0
