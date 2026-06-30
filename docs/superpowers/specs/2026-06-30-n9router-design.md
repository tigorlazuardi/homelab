# n9router service — design

Date: 2026-06-30
Status: approved (design), pending implementation plan

## Goal

Add **9router** (decolua/9router) to the homelab: a self-hosted, OpenAI-compatible
AI API proxy that fronts 40+ LLM providers with auto-fallback. Coding tools (Claude
Code, Codex, Cursor, etc.) point at it instead of each provider directly.

## Decisions (locked)

| Decision | Value | Rationale |
|---|---|---|
| Exposure | Public vhost `9router.tigor.web.id` | Coding tools reach it from anywhere. |
| Image | `ghcr.io/decolua/9router:latest`, `autoUpdate="registry"` | User override: must track latest to keep up with newest supported LLM models. Accepts supply-chain risk of auto-pulling `:latest` on an internet-facing credential proxy. |
| Auth — dashboard | Native OIDC → new dex static client | App's own SSO; no tinyauth. |
| Auth — proxy API | `REQUIRE_API_KEY=true` | Public endpoint must not be an open relay on provider creds. |
| Port | 20128 | App default. |
| Data | `/var/mnt/state/n9router` (SSD/state tier) → `/app/data` | sqlite db (`$DATA_DIR/db/data.sqlite`), small high-R/W config. |

Native OIDC is configured in the n9router **dashboard UI at runtime** (issuer, client
id/secret, callback) — stored in sqlite, NOT via env. The dex static client's
`redirectURIs` must exactly match the callback the n9router UI displays at cutover.

## Service definition (`services/n9router.nix`, helper pattern)

Entrypoint runs as **root**, does `chown -R node:node /app/data`, then `su-exec node`
(node = uid 1000). So it needs caps → `harden = false` (su-exec needs SETUID/SETGID,
chown needs CHOWN); `uid = 1000` so keep-id maps the final `node` process to host srv.

```nix
homelab.containers.n9router = {
  image = "ghcr.io/decolua/9router:latest";
  autoUpdate = "registry";                              # track latest LLM-model support (user override)
  port = 20128;
  subdomain = "9router";
  uid = 1000;                                           # node user → keep-id → host srv
  harden = false;                                       # entrypoint chowns + su-exec; needs caps
  environments = {
    DATA_DIR = "/app/data";
    NODE_ENV = "production";
    PORT = "20128";
    NEXT_PUBLIC_BASE_URL = "https://9router.tigor.web.id";
    BASE_URL = "https://9router.tigor.web.id";
    AUTH_COOKIE_SECURE = "true";
    OBSERVABILITY_ENABLED = "true";
    REQUIRE_API_KEY = "true";
  };
  environmentFiles = [ config.sops.secrets."n9router.env".path ];
  volumes = [ "/var/mnt/state/n9router:/app/data" ];
  tmpfiles = [ "d /var/mnt/state/n9router 0750 srv srv -" ];
};
```

Registered in `services/default.nix`.

## Secret (`secrets/n9router.env`, sops dotenv, `owner=srv`)

Generated random values:
- `JWT_SECRET` — signs the dashboard `auth_token` cookie.
- `INITIAL_PASSWORD` — first dashboard login (before OIDC wired).
- `API_KEY_SECRET` — proxy API key secret.
- `MACHINE_ID_SALT` — machine-id salt.

Encrypt with `sops encrypt -i secrets/n9router.env` before commit. Public repo —
plaintext never committed (secrets rule).

## dex static client (`secrets/dex.yaml`, sops — requires explicit decrypt OK)

Add under `staticClients`:

```yaml
- id: 9router
  name: 9router
  secret: <generated>
  redirectURIs: [ "https://9router.tigor.web.id/<callback>" ]   # exact path from n9router UI at cutover
```

Same `secret` entered in the n9router dashboard OIDC settings (runtime, app-side).

## Telemetry

- **Logs**: container stdout/stderr flow into the existing podman → loki pipeline
  automatically (no extra wiring).
- **Metrics**: `OBSERVABILITY_ENABLED=true`. TODO(cutover): determine whether the app
  exposes a Prometheus `/metrics` endpoint; if yes, add an alloy/prometheus scrape
  target. If it emits OTLP, point it at the native alloy gateway (4317/4318).
- **Traces**: only if the app supports OTLP export — investigate at cutover.

## Files touched

1. `services/n9router.nix` — new helper service.
2. `services/default.nix` — import the new module.
3. `secrets/n9router.env` — new, sops-encrypted.
4. `secrets/dex.yaml` — add `9router` static client.

## Acceptance

- `nixos-rebuild build --flake .#homeserver` succeeds (build-only; runtime proven at
  switch per conventions — do NOT switch until deliberate cutover).
- No plaintext secret committed (`git grep` clean; every `secrets/*` has `ENC[`).

## Cutover TODOs (runtime, not provable at build)

- Verify `/var/mnt/state/n9router` ends up owned `srv:srv` after the entrypoint
  chown + su-exec (keep-id mapping of node→srv).
- Read exact OIDC callback path from the n9router UI; set dex `redirectURIs` to match.
- Wire dex client secret into the n9router dashboard.
- Confirm metrics endpoint; add scrape if present.
