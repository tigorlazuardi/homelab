---
description: Publish visual-plan / visual-recap MDX to the self-hosted plan renderer.
paths:
  - "services/plan.nix"
  - "scripts/plan-emit.sh"
  - "plans/**"
---

# Plan app (self-hosted MDX renderer)

`plan.tigor.web.id` (tinyauth-gated) renders MDX plans from a local dir. It is the
self-hosted renderer for **visual-plan** and **visual-recap** output on this host.
Container loopback `127.0.0.1:3050`; runs in local no-login mode. Deploy details:
`services/plan.nix`, `containers/plan/Containerfile`, `plans/plan-app/`.

## How rendering works

- Plans live in `/var/mnt/state/plan/plans` (`2770 srv media`). Each plan = one
  subfolder `<slug>/plan.mdx` (+ optional `canvas.mdx`, `prototype.mdx`).
- Browse `plan.tigor.web.id/local-plans/<slug>` to render `<slug>/plan.mdx`.
- Round-trips: edits in the UI mirror back to the file (app is `srv`, group `media`).

## Access = direct URL only (no sidebar listing)

Local-dir plans do NOT appear in the app sidebar — that's hard-wired in 0.63.4:
the sidebar list is session-gated and queries the DB (`list-visual-plans`), never
`PLAN_LOCAL_DIR`; there is no enumerate action and no `/local-plans` index route
(`/local-plans` → 404). So reach each plan by its **direct URL**
`plan.tigor.web.id/local-plans/<slug>` (`plan-emit.sh` prints it). Sidebar listing
would require forking the template — not pursued.

**Local mode must be ON or the page renders empty.** The single-plan fetch
(`get-local-plan-folder`) is public only when `isLocalPlanRuntime()` is true, which
needs `NODE_ENV=development` (the build hard-refuses local mode under `production`)
+ `PLAN_LOCAL_MODE=1`, `AUTH_MODE` unset. These are set in `services/plan.nix`. If
local actions 401, verify they reached the process:
`sudo -u srv XDG_RUNTIME_DIR=/run/user/1001 podman exec plan printenv NODE_ENV PLAN_LOCAL_MODE`.

## Emitting a plan — use the helper

When you produce a visual-plan or visual-recap as MDX on this host, publish it:

```bash
scripts/plan-emit.sh <slug> path/to/plan.mdx     # or: cat plan.mdx | scripts/plan-emit.sh <slug>
```

It writes `<base>/<slug>/plan.mdx`, fixes perms so the app can mirror edits, then
reports the render URL.

## Self-hosted: tolerate the app being down

The box hosts the app itself, so `plan.service` may be down (rebuild, crash, OOM).
**Writing the MDX is a plain host-dir write — it does NOT need the container.** The
plan persists and renders whenever the app next comes up. So:

- Emit the file regardless of app state; never block plan authoring on the renderer.
- `plan-emit.sh` probes `:3050` after writing: if up, prints the render URL; if down,
  warns that render is deferred and hints the start command. It **exits 0 either way** —
  the durable write is the success condition.
- The only hard failure is the base dir missing/unwritable (mount gone / undeployed) —
  then the write genuinely can't happen.
- Start the app if needed:
  `sudo -u srv XDG_RUNTIME_DIR=/run/user/1001 systemctl --user start plan.service`
  (run from a srv-readable cwd — see [[srv-podman]] for the `cd /tmp` gotcha).
