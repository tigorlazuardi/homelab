# Deploy Agent-Native Plans app (self-hosted)

Render MDX plans (visual-plan / visual-recap output) at `https://plan.tigor.web.id`.

## Decisions (locked)

- **Build**: multi-stage Containerfile, scaffold from GitHub at build, `pnpm build`.
  Local image `localhost/plan:latest`, run via the `homelab.containers` quadlet helper.
  First locally-built image in this repo (all others pull a registry).
- **Auth**: app runs in local no-login mode; whole vhost gated by tinyauth (`auth = true`).
- **DB**: SQLite `file:/data/app.db` (self-creates schema on boot). No extra container.
- **Domain**: `plan.tigor.web.id`. hostPort **3050** (3000 = adguard LAN — avoid).
- **CPU**: `media-batch.slice` (light, bursty render).

## Key runtime facts (from source research)

- Stack: React Router 7 + Nitro + Vite, **Node 22**. Entry `node .output/server/index.mjs`.
- Native modules: `better-sqlite3` + `node-pty` → compile in `node:22-bookworm` (has
  gcc/g++/make/python3 already), run on `node:22-bookworm-slim` (same glibc 2.36 ABI).
- Scaffold is fully non-interactive: `npx --yes @agent-native/core@latest create my-plans --standalone --template plan` (the `--yes` is npx's confirm). Needs network + git at build.
- Scaffold does **not** run install — run `pnpm install` (corepack) then `pnpm build` separately.
- **TRAP — no-login mode**: local-plan action endpoints are refused when `NODE_ENV=production`.
  MUST set `NODE_ENV=development` **and** `PLAN_LOCAL_MODE=1`. Page routes are public either way.
- `PLAN_LOCAL_DIR` = read-WRITE mirror dir (app writes `<slug>/plan.mdx`). Mount writable.
- `BETTER_AUTH_SECRET` — set via sops (mandatory in prod; harmless in dev). `BETTER_AUTH_URL` = public URL.

## Files

1. `containers/plan/Containerfile` — multi-stage (build → slim runtime). No `pnpm prune` (keep
   native addons). `USER node` (uid 1000) before CMD so keep-id maps writes to host `srv`.
2. `secrets/plan.env` — sops dotenv, `BETTER_AUTH_SECRET=<openssl rand -hex 32>`. Encrypt before commit.
3. `services/plan.nix` — `homelab.containers.plan` + `sops.secrets."plan-env"` (owner srv, dotenv).
4. `services/default.nix` — add `./plan.nix`.
5. `scripts/build-plan-image.sh` — build image as `srv` user (rootless store).
6. `.claude/rules/adding-services.md` — register port 3050 plan.

## services/plan.nix shape

```nix
{ config, ... }:
{
  sops.secrets."plan-env" = {
    sopsFile = ../secrets/plan.env;
    format = "dotenv";
    key = "";
    owner = "srv";
  };
  homelab.containers.plan = {
    image = "localhost/plan:latest";
    autoUpdate = "local";            # never pull a registry for a local image
    port = 3000;                     # container port
    hostPort = 3050;                 # loopback publish (3000 = adguard)
    uid = 1000;                      # node user → keep-id → host srv
    auth = true;                     # tinyauth whole vhost
    volumes = [
      "/var/mnt/state/plan/data:/data"
      "/var/mnt/state/plan/plans:/plans"
    ];
    environments = {
      TZ = "Asia/Jakarta";
      NODE_ENV = "development";      # REQUIRED for local no-login actions (not production)
      PLAN_LOCAL_MODE = "1";
      PORT = "3000";
      DATABASE_URL = "file:/data/app.db";
      BETTER_AUTH_URL = "https://plan.tigor.web.id";
      PLAN_LOCAL_DIR = "/plans";
    };
    environmentFiles = [ config.sops.secrets."plan-env".path ];
    extraContainerConfig = { pull = "never"; };
    serviceConfig = { Slice = "media-batch.slice"; };
    tmpfiles = [
      "d /var/mnt/state/plan 0750 srv srv -"
      "d /var/mnt/state/plan/data 0750 srv srv -"
      "d /var/mnt/state/plan/plans 0750 srv srv -"
    ];
  };
}
```

## Order of operations (host, after merge)

1. `nixos-rebuild build --flake .#homeserver` (validates nix) — must pass before commit.
2. Build image as srv: `scripts/build-plan-image.sh`.
3. `nixos-rebuild switch` → starts the quadlet unit. Verify `https://plan.tigor.web.id`
   (tinyauth login) → `/local-plans/test` renders empty (route + PLAN_LOCAL_DIR wired).

## PLAN_LOCAL_DIR wiring (resolved)

Central write-target, NOT per-repo symlink (plans come from many repos; app wants a flat
`<slug>/plan.mdx`, repo plans are nested `.md`).

- `PLAN_LOCAL_DIR=/plans` (container) → host `/var/mnt/state/plan/plans`, perms **`2770 srv media`**
  (setgid + group `media`) so `homeserver` (member of `media`) can write MDX; container `srv` keeps R/W.
  The sqlite `data` dir stays `0750 srv srv` (private).
- Workflow: write `/var/mnt/state/plan/plans/<slug>/plan.mdx` → browse `plan.tigor.web.id/local-plans/<slug>`.
  Round-trips: UI edits mirror back to the file.
- Each plan = one subfolder; `plan.mdx` is the content (+ optional `canvas.mdx`, `prototype.mdx`).

Perms apply on next `nixos-rebuild switch` (tmpfiles resets the existing dir's mode/owner).
