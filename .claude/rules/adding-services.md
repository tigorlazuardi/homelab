---
description: How to add or edit a service in this homelab (rootless quadlet pattern).
paths:
  - "services/**"
  - "modules/quadlet-service.nix"
---

# Adding a service

All app services run **rootless** under the `srv` user via quadlet-nix. Edge
services (privileged ports / kernel) stay **native**. See `docs/architecture.md`.

## Single-container service → use the helper

Declare `homelab.containers.<name>` (see `modules/quadlet-service.nix`). Minimal:

```nix
{
  homelab.containers.foo = {
    image = "ghcr.io/owner/foo:latest";
    port = 8080;          # container port; nginx vhost <name>.tigor.web.id auto-created
    uid = 1000;           # app's uid inside image → keep-id maps it to host srv
    volumes = [ "/srv/data/state/foo:/config" ];
    environments = { TZ = "Asia/Jakarta"; };
    tmpfiles = [ "d /srv/data/state/foo 0750 srv srv -" ];
  };
}
```

Helper knobs: `port`/`hostPort` (host loopback; default = port), `subdomain`,
`uid`/`gid`/`user`, `userns` (null = default rootless), `harden`, `volumes`,
`environments`, `environmentFiles`, `extraContainerConfig`, `nginx.extraConfig`,
`tmpfiles`. Defaults: `userns=keep-id:uid=<uid>`, `harden=true` (cap-drop all +
no-new-privileges), `autoUpdate="registry"`.

## Multi-container (needs a private network) → write it explicitly

The helper is single-container. Stacks (e.g. searxng, paperless, infisical) need a
private rootless network whose `.ref` must be taken **inside the Home Manager user
scope**. Mirror `services/paperless-ngx.nix`:

```nix
home-manager.users.srv = { config, ... }:
  let inherit (config.virtualisation.quadlet) networks; in {
    virtualisation.quadlet = {
      networks.foo = { };
      containers.foo-app = { containerConfig = { networks = [ networks.foo.ref ]; ... }; };
      containers.foo-db  = { containerConfig = { networks = [ networks.foo.ref ]; ... }; };
    };
  };
```

## Rules of thumb

- **File ownership (the keep-id rule).** Set `uid` = the uid the image runs as
  inside, so files land owned by host `srv` (not a subuid). If the image defaults
  to root, also set `user = "<uid>:<gid>"` to force it.
- **s6 / linuxserver / jlesage images** init as root and need caps → set
  `harden = false`. Either `userns = null` (run as root-in-userns → host srv, set
  `USER_ID=0`) or `keep-id:uid=<PUID>` with `PUID`/`PGID`.
- **Reader vs writer.** Media consumers mount data `:ro` (e.g. jellyfin,
  navidrome); only downloaders/importers get `:rw`. Never give a reader write.
- **Networking.** Publish to `127.0.0.1` only — nginx is the sole ingress.
  Inter-service across separate stacks: `http://host.containers.internal:<port>`.
  Containers in the same private network resolve each other by name.
- **tmpfiles.** Shared data dirs `2775 srv media` (setgid → human user in `media`
  can access). Private state/db dirs `0750 srv srv` (or `0700` for postgres).
- **Secrets** → see the secrets rule. Rootless containers need `owner = "srv"`.
- **Edge services** (nginx/adguard/wireguard/samba/smartd) are NOT rootless —
  keep them native (privileged ports / kernel).

## Host port registry (avoid collisions)

| port | service | | port | service |
|---|---|---|---|---|
| 4533 | navidrome | | 8080 | searxng |
| 4567 | suwayomi | | 8082 | ytptube |
| 5173 | wallrus  | | 8083 | qbittorrent (UI; 6881 BT) |
| 5800 | jdownloader | | 8084 | infisical |
| 8000 | paperless | | 8191 | flaresolverr |
| 9000 | webhook (native) | | | |

## Before committing

Run `nixos-rebuild build --flake .#homeserver` — it must succeed. Build validates
nix + quadlet syntax; rootless **runtime** behaviour (keep-id ownership, s6,
secret readability) is only proven at switch — leave a `TODO(cutover)` for those.
