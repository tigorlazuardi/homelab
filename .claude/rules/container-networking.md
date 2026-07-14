---
description: Rules for rootless container networking.
paths:
  - "services/**.nix"
  - "modules/quadlet-service.nix"
---

# Container networking (rootless pasta)

## The hard limitation (confirmed)

Rootless podman 5.x uses **pasta**. Pasta **cannot hairpin** a container back to a
service bound on the **host loopback** (`127.0.0.1`). A container connecting to
`host.containers.internal` (→ `169.254.1.2`) gets **`connection refused`** for any
host service published as `127.0.0.1:<port>`.

Confirmed by test (2026-06-19):
- `grafana` → `http://host.containers.internal:3100` (loki) → refused.
- `prowlarr` → `http://host.containers.internal:8989` (sonarr) → refused.

Host→container still works (published loopback ports are reachable FROM the host):
nginx → container, and native Alloy → prometheus/loki/tempo, all fine. **Only the
container → host-loopback direction is broken.**

## The rule

**Container-to-container traffic MUST go over a shared podman network, resolving
peers by container name** — never `host.containers.internal`, never `127.0.0.1`.
This is already the pattern for immich, paperless, searxng, observability.

- Put every container that must talk to another on the **same** network.
- Address peers by **container name + the peer's CONTAINER (internal) port**, e.g.
  `http://sonarr:8989`, `http://flaresolverr:8191`, `http://loki:3100`. NOT the
  host-published port (`hostPort`), NOT a loopback/LAN IP.
- `publishPorts` (loopback) still belong on a service — they serve **nginx ingress**
  and **native host producers** (Alloy push), both host→container. Keep them.

## Exceptions

- **Reaching a NATIVE host service** (nginx, adguard) from a container: use
  `addHosts = [ "<host>:host-gateway" ]` and address it by its public vhost so
  nginx routes by `Host` header (see `services/immich.nix` → dex). pasta routes the
  gateway even with `--no-map-gw` via the added host entry.
- A container that talks to **nothing** internal needs no network.

## The shared media network (`arr`)

The media-automation stack + jellyfin + seerr + suwayomi share one network named
`arr` so they resolve each other by name (prowlarr↔arr, arr→qbittorrent,
*→flaresolverr, recyclarr→arr, seerr→sonarr/radarr/jellyfin, suwayomi→flaresolverr).

## Using a shared network from the helper

`modules/quadlet-service.nix` exposes a `networks` knob (list of declared network
names). Opt a helper service in with:

```nix
homelab.containers.foo = {
  # ...
  networks = [ "arr" ];   # joins the shared media network
};
```

The helper looks up each name's `.ref` inside the Home Manager `srv` scope (the
reason multi-container stacks were hand-written before). The `arr` network itself
is declared once in the helper's `srv` quadlet scope. To add a NEW shared network,
declare `home-manager.users.srv.virtualisation.quadlet.networks.<name> = { };` in
the srv scope, then reference it by name in the knob.

## App-side wiring is runtime

URLs between apps configured in each app's **web UI / config DB** (prowlarr indexer
proxy, arr download client, seerr service setup) are NOT in nix — switch the nix
`networks` first, then set those URLs to `http://<container>:<port>`. The few that
ARE nix (e.g. suwayomi `FLARESOLVERR_URL`) move to the container-name form.
