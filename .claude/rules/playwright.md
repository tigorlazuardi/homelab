---
description: Playwright browsers run via podman, never via nix — avoids the nixpkgs version-skew treadmill.
paths:
  - "modules/home/agents.nix"
  - "scripts/**"
---

# Playwright = podman, not nix

**Decision (2026-06-20):** any project on this host that needs Playwright runs it
through the official **podman image**, NOT through nixpkgs `playwright-driver`.

## Why not nix

On NixOS, browsers downloaded by `npm install playwright` don't run (no FHS loader,
missing libs). The nix workaround — `pkgs.playwright-driver.browsers` + env vars —
forces the npm `playwright` version to match the nixpkgs driver version **exactly**.
nixpkgs lags upstream by weeks, so every project that bumps Playwright re-breaks until
nixpkgs catches up. With multiple projects on different versions, that's a constant
fight. So Playwright is intentionally absent from `modules/home/agents.nix`.

## The podman way

The official image ships browsers + all system deps, matched to one exact Playwright
version. Each project picks the tag that matches its own `package.json` — fully
self-consistent, no nix coupling, bump anytime.

```bash
# tag MUST match the project's playwright version (check package.json)
podman run --rm --init -v "$PWD":/work -w /work \
  mcr.microsoft.com/playwright:v1.XX.Y-noble \
  npx playwright test "$@"
```

- Headless by default. For headed/UI mode, mount X or use the MCP `--isolated` flow.
- Rootless `srv` not required — Playwright dev runs as the `homeserver` user. Mind the
  [[srv-podman]] cwd + fully-qualified-image gotchas if ever run under `srv`.
- Image is fully-qualified (`mcr.microsoft.com/...`) — rootless podman needs that.

## Redirect

When a project here asks to add Playwright via nix / home-manager, **don't**. Point it
at this podman pattern instead. Keep `agents.nix` Playwright-free.
