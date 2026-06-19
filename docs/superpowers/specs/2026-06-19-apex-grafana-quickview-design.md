# Design — `tigor.web.id` apex system quick-view

Date: 2026-06-19
Status: approved (pre-implementation)

## Goal

Make the bare apex domain `tigor.web.id` (no subdomain, no subpath in the
address bar) show a **read-only, at-a-glance system-performance dashboard** for
the homeserver, sourced from the existing Grafana, guarded by tinyauth — so the
sole user can glance at host health from a phone or a remote laptop with a single
passkey tap and no Grafana login.

`grafana.tigor.web.id` stays a **full-blown Grafana** for deep-dives and editing.

## Constraints / facts (verified in repo)

- Grafana already runs rootless under `srv`, published on host loopback
  `127.0.0.1:3300`, vhost `grafana.tigor.web.id`, own admin login, **no tinyauth**
  today. `GF_SERVER_ROOT_URL`/`GF_SERVER_DOMAIN` = `grafana.tigor.web.id`.
- Host metrics already flow: native Alloy runs `prometheus.exporter.unix`
  (`node_*` series) → Prometheus. No new exporter needed.
- No Grafana dashboards are provisioned yet (only datasources + alerting).
- ACME: a single cert `certs."tigor.web.id"` has the **apex as CN** plus every
  `*.tigor.web.id` vhost as SANs. A new apex vhost needs no cert work
  (`useACMEHost` defaults to `"tigor.web.id"`).
- tinyauth is a per-vhost toggle declared in `services/auth.nix`:
  `services.nginx.virtualHosts.<h>.tinyauth.enable = true` gates a hand-written
  vhost. Session cookie is shared across `*.tigor.web.id` (30-day expiry).
- **Grafana anonymous access is instance-wide** — it cannot be on for one vhost
  and off for another on the same Grafana instance. This drives the auth model.

## Architecture

Apex and subdomain are **two nginx doors to the same Grafana instance**. The
apex door proxies Grafana and redirects the root path to one dashboard in kiosk
mode; the subdomain door is unchanged Grafana.

```
phone/laptop ──► tigor.web.id ──(tinyauth gate)──► nginx proxy ─► grafana:3300
                    location = /  →  302 /d/system-perf/system-performance?kiosk&theme=dark
                    location /    →  proxy_pass (HTML + assets + /api, same-origin)

             ──► grafana.tigor.web.id ──(tinyauth gate)──► nginx proxy ─► grafana:3300
                    full Grafana UI (anonymous = Viewer; admin login for edits)
```

### Same-origin decision (load-bearing)

`root_url` stays `grafana.tigor.web.id`. Grafana's frontend issues API/datasource
queries against **root-relative** paths (`appSubUrl` = `/`), not the absolute
`root_url` host, so a page served at the apex makes its `/api/...` XHR to the
apex origin → nginx proxies to Grafana → **same-origin, no CORS**. Anonymous
access means no login redirect (which would use `root_url`) ever fires for the
kiosk view. Therefore `root_url`/`domain` need **not** change, and the subdomain's
behavior is undisturbed.

This assumption MUST be verified after switch (see Acceptance).

## Components / changes

### 1. `services/observability.nix` — Grafana (additive)

Add to the grafana container `environments`:

- `GF_AUTH_ANONYMOUS_ENABLED = "true"`
- `GF_AUTH_ANONYMOUS_ORG_ROLE = "Viewer"`
- `GF_AUTH_ANONYMOUS_HIDE_VERSION = "true"`

(Admin password env stays; signups stay off. Editing still requires admin login.)

Add a **dashboard provisioning provider** + the dashboard JSON, mirroring the
existing `grafanaDatasources` mount pattern:

- A `dashboards.yaml` provider (apiVersion 1) pointing at a mounted folder,
  `allowUiUpdates` may stay default; `foldersFromFilesStructure` not needed.
- `system-performance.json` mounted read-only into the provider folder.
- Both mounted into the container under
  `/etc/grafana/provisioning/dashboards/…` and the dashboards dir respectively.

### 2. System Performance dashboard (`system-performance.json`)

- **uid:** `system-perf` (fixed — the apex redirect path depends on it).
- **title:** `System Performance`; default time range `now-1h`; refresh `30s`;
  dark theme; tags `["system","host"]`.
- Datasource: the provisioned Prometheus (`uid = prometheus`).
- Panels (compact, phone-readable in kiosk; ~9):
  1. **CPU %** (stat/gauge): `100 - (avg(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)`
  2. **Load** (stat, 3 series): `node_load1`, `node_load5`, `node_load15`
  3. **RAM %** (gauge): `(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100`
  4. **Swap %** (gauge): `(1 - node_memory_SwapFree_bytes / node_memory_SwapTotal_bytes) * 100`
  5. **Disk used %** (bar gauge, per mount) for mountpoints
     `/`, `/var/mnt/state`, `/var/mnt/wolf`, `/var/mnt/fenrir`, `/var/mnt/nas`:
     `100 - (node_filesystem_avail_bytes{mountpoint=~"<list>"} / node_filesystem_size_bytes * 100)`
     (exclude tmpfs/overlay via `fstype!~"tmpfs|overlay|squashfs"`).
  6. **Disk IO** (timeseries): `rate(node_disk_read_bytes_total[5m])` /
     `rate(node_disk_written_bytes_total[5m])`.
  7. **Network** (timeseries): `rate(node_network_receive_bytes_total{device!~"lo|veth.*|podman.*|cni.*"}[5m])`
     / `…transmit…`.
  8. **Uptime** (stat): `node_time_seconds - node_boot_time_seconds` (unit: seconds → duration).
  9. **CPU temp** (stat): `node_hwmon_temp_celsius` (tolerate empty — panel shows
     "No data" if the box exposes no hwmon sensor; not an error).

### 3. `services/observability.nix` / nginx vhosts

- **Existing** `grafana.tigor.web.id` vhost: add `tinyauth.enable = true;`
  (required because anonymous is now instance-wide — without the gate the
  subdomain would be anonymously world-readable).
- **New** apex vhost `tigor.web.id`:
  - `forceSSL = true;` (cert + `useACMEHost` default already cover it)
  - `tinyauth.enable = true;`
  - `locations."= /".extraConfig = "return 302 /d/system-perf/system-performance?kiosk&theme=dark;";`
  - `locations."/".proxyPass = "http://127.0.0.1:3300";`

## Out of scope (YAGNI)

- No `root_url`/`domain` change. No auth-proxy/header trust. No Grafana public
  dashboards. No Node Exporter Full import. No per-user identity (single user).
- No new exporter — `node_*` already scraped.

## Acceptance criteria

1. `nixos-rebuild build --flake .#homeserver` passes.
2. After switch: hitting `https://tigor.web.id` from a fresh browser →
   tinyauth login → lands on the kiosk dashboard (no menus/nav), **panels render
   data** (confirms same-origin assumption), address bar stays `tigor.web.id`.
3. `https://grafana.tigor.web.id` → tinyauth → full Grafana; admin login still
   works for editing; anonymous view is read-only.
4. Neither host is reachable without passing tinyauth (no world-readable Grafana).
5. CPU-temp panel empty is acceptable; all other panels show data.

## Rollout

Build-only is safe. Applying needs `nixos-rebuild switch` (restarts grafana
container + reloads nginx). Verify criteria 2–4 on the live host post-switch.
