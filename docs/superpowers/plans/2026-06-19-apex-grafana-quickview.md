# Apex Grafana System Quick-View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Serve a read-only at-a-glance system-performance dashboard at the bare apex `tigor.web.id`, gated by tinyauth, sourced from the existing Grafana — while `grafana.tigor.web.id` stays full-blown Grafana.

**Architecture:** Two nginx vhosts front the same loopback Grafana (`127.0.0.1:3300`). Apex proxies Grafana and 302-redirects `/` to one dashboard in kiosk mode; both vhosts are tinyauth-gated. Grafana gets instance-wide anonymous=Viewer so the kiosk needs no Grafana login. `root_url` is unchanged because Grafana's in-page API calls are root-relative (so the apex page stays same-origin).

**Tech Stack:** NixOS, home-manager, quadlet-nix (rootless podman), Grafana provisioning (datasources + dashboards), nginx, tinyauth forward-auth, Prometheus `node_*` (node exporter via Alloy `prometheus.exporter.unix`).

## Global Constraints

- Build gate (every task): `cd ~/homelab && nixos-rebuild build --flake .#homeserver` MUST pass. Build-only; do NOT `switch` (live host, per repo rule).
- Conventional-commit messages. Commit at the end of each task. Do NOT push unless the orchestrator/user asks.
- Dashboard uid is exactly `system-perf` (the apex redirect path depends on it).
- Prometheus datasource uid is exactly `prometheus` (already provisioned in `observability.nix`).
- Single user; read-only kiosk. No `root_url`/`domain` change, no auth-proxy, no public dashboards, no Node Exporter Full, no new exporter (YAGNI per spec).
- All Grafana env values are strings (quadlet `environments` attrset → string values only).

---

### Task 1: System Performance dashboard JSON

**Files:**
- Create: `services/grafana-dashboards/system-performance.json`

**Interfaces:**
- Produces: a Grafana dashboard with `"uid": "system-perf"`, title `System Performance`, consumed by Task 2's provisioning provider and Task 3's apex redirect path `/d/system-perf/system-performance`.

- [ ] **Step 1: Create the dashboard JSON**

Create `services/grafana-dashboards/system-performance.json` with this exact content:

```json
{
  "uid": "system-perf",
  "title": "System Performance",
  "tags": ["system", "host"],
  "timezone": "browser",
  "schemaVersion": 39,
  "version": 1,
  "editable": false,
  "refresh": "30s",
  "time": { "from": "now-1h", "to": "now" },
  "templating": { "list": [] },
  "annotations": { "list": [] },
  "panels": [
    {
      "type": "gauge", "title": "CPU %", "id": 1,
      "gridPos": { "h": 6, "w": 6, "x": 0, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "fieldConfig": { "defaults": { "unit": "percent", "min": 0, "max": 100, "thresholds": { "mode": "absolute", "steps": [ { "color": "green", "value": null }, { "color": "yellow", "value": 70 }, { "color": "red", "value": 90 } ] } }, "overrides": [] },
      "targets": [ { "refId": "A", "datasource": { "type": "prometheus", "uid": "prometheus" }, "expr": "100 - (avg(irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)" } ]
    },
    {
      "type": "stat", "title": "Load (1/5/15)", "id": 2,
      "gridPos": { "h": 6, "w": 6, "x": 6, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "fieldConfig": { "defaults": { "unit": "short", "decimals": 2 }, "overrides": [] },
      "options": { "graphMode": "none", "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false } },
      "targets": [
        { "refId": "A", "datasource": { "type": "prometheus", "uid": "prometheus" }, "expr": "node_load1", "legendFormat": "1m" },
        { "refId": "B", "datasource": { "type": "prometheus", "uid": "prometheus" }, "expr": "node_load5", "legendFormat": "5m" },
        { "refId": "C", "datasource": { "type": "prometheus", "uid": "prometheus" }, "expr": "node_load15", "legendFormat": "15m" }
      ]
    },
    {
      "type": "gauge", "title": "RAM %", "id": 3,
      "gridPos": { "h": 6, "w": 6, "x": 12, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "fieldConfig": { "defaults": { "unit": "percent", "min": 0, "max": 100, "thresholds": { "mode": "absolute", "steps": [ { "color": "green", "value": null }, { "color": "yellow", "value": 75 }, { "color": "red", "value": 90 } ] } }, "overrides": [] },
      "targets": [ { "refId": "A", "datasource": { "type": "prometheus", "uid": "prometheus" }, "expr": "(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100" } ]
    },
    {
      "type": "gauge", "title": "Swap %", "id": 4,
      "gridPos": { "h": 6, "w": 6, "x": 18, "y": 0 },
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "fieldConfig": { "defaults": { "unit": "percent", "min": 0, "max": 100, "thresholds": { "mode": "absolute", "steps": [ { "color": "green", "value": null }, { "color": "yellow", "value": 50 }, { "color": "red", "value": 80 } ] } }, "overrides": [] },
      "targets": [ { "refId": "A", "datasource": { "type": "prometheus", "uid": "prometheus" }, "expr": "(1 - node_memory_SwapFree_bytes / clamp_min(node_memory_SwapTotal_bytes, 1)) * 100" } ]
    },
    {
      "type": "bargauge", "title": "Disk used % (per mount)", "id": 5,
      "gridPos": { "h": 7, "w": 12, "x": 0, "y": 6 },
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "fieldConfig": { "defaults": { "unit": "percent", "min": 0, "max": 100, "thresholds": { "mode": "absolute", "steps": [ { "color": "green", "value": null }, { "color": "yellow", "value": 80 }, { "color": "red", "value": 90 } ] } }, "overrides": [] },
      "options": { "orientation": "horizontal", "displayMode": "gradient", "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false } },
      "targets": [ { "refId": "A", "datasource": { "type": "prometheus", "uid": "prometheus" }, "expr": "100 - (node_filesystem_avail_bytes{mountpoint=~\"/|/var/mnt/state|/var/mnt/wolf|/var/mnt/fenrir|/var/mnt/nas\",fstype!~\"tmpfs|overlay|squashfs\"} / node_filesystem_size_bytes * 100)", "legendFormat": "{{ mountpoint }}" } ]
    },
    {
      "type": "timeseries", "title": "Disk IO", "id": 6,
      "gridPos": { "h": 7, "w": 12, "x": 12, "y": 6 },
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "fieldConfig": { "defaults": { "unit": "Bps", "custom": { "drawStyle": "line", "fillOpacity": 10 } }, "overrides": [] },
      "targets": [
        { "refId": "A", "datasource": { "type": "prometheus", "uid": "prometheus" }, "expr": "sum(rate(node_disk_read_bytes_total[5m]))", "legendFormat": "read" },
        { "refId": "B", "datasource": { "type": "prometheus", "uid": "prometheus" }, "expr": "sum(rate(node_disk_written_bytes_total[5m]))", "legendFormat": "write" }
      ]
    },
    {
      "type": "timeseries", "title": "Network", "id": 7,
      "gridPos": { "h": 7, "w": 12, "x": 0, "y": 13 },
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "fieldConfig": { "defaults": { "unit": "Bps", "custom": { "drawStyle": "line", "fillOpacity": 10 } }, "overrides": [] },
      "targets": [
        { "refId": "A", "datasource": { "type": "prometheus", "uid": "prometheus" }, "expr": "sum(rate(node_network_receive_bytes_total{device!~\"lo|veth.*|podman.*|cni.*\"}[5m]))", "legendFormat": "rx" },
        { "refId": "B", "datasource": { "type": "prometheus", "uid": "prometheus" }, "expr": "sum(rate(node_network_transmit_bytes_total{device!~\"lo|veth.*|podman.*|cni.*\"}[5m]))", "legendFormat": "tx" }
      ]
    },
    {
      "type": "stat", "title": "Uptime", "id": 8,
      "gridPos": { "h": 7, "w": 6, "x": 12, "y": 13 },
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "fieldConfig": { "defaults": { "unit": "s" }, "overrides": [] },
      "options": { "graphMode": "none", "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false } },
      "targets": [ { "refId": "A", "datasource": { "type": "prometheus", "uid": "prometheus" }, "expr": "node_time_seconds - node_boot_time_seconds" } ]
    },
    {
      "type": "stat", "title": "CPU temp", "id": 9,
      "gridPos": { "h": 7, "w": 6, "x": 18, "y": 13 },
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "fieldConfig": { "defaults": { "unit": "celsius", "thresholds": { "mode": "absolute", "steps": [ { "color": "green", "value": null }, { "color": "yellow", "value": 70 }, { "color": "red", "value": 85 } ] } }, "overrides": [] },
      "options": { "graphMode": "none", "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false } },
      "targets": [ { "refId": "A", "datasource": { "type": "prometheus", "uid": "prometheus" }, "expr": "max(node_hwmon_temp_celsius)" } ]
    }
  ]
}
```

- [ ] **Step 2: Validate the JSON parses**

Run: `jq -e '.uid == "system-perf" and (.panels | length) == 9' ~/homelab/services/grafana-dashboards/system-performance.json`
Expected: prints `true`, exit 0.

- [ ] **Step 3: Commit**

```bash
cd ~/homelab
git add services/grafana-dashboards/system-performance.json
git commit -m "feat(observability): system-perf quick-view dashboard JSON"
```

---

### Task 2: Grafana anonymous access + dashboard provisioning

**Files:**
- Modify: `services/observability.nix` (the `grafanaDatasources` `let`-block area; the grafana container `volumes` + `environments`)

**Interfaces:**
- Consumes: `services/grafana-dashboards/system-performance.json` (Task 1).
- Produces: Grafana serving the `system-perf` dashboard and allowing anonymous Viewer access — relied on by Task 3's kiosk redirect.

- [ ] **Step 1: Add a dashboards provider next to `grafanaDatasources`**

In `services/observability.nix`, in the `let` block right after the
`grafanaDatasources = yaml.generate ...;` binding, add:

```nix
  # Dashboard provisioning provider — loads JSON dashboards from a mounted dir.
  grafanaDashboardsProvider = yaml.generate "dashboards.yaml" {
    apiVersion = 1;
    providers = [
      {
        name = "default";
        type = "file";
        disableDeletion = true;
        allowUiUpdates = false;
        options.path = "/etc/grafana/provisioning/dashboards/json";
        options.foldersFromFilesStructure = false;
      }
    ];
  };
```

- [ ] **Step 2: Mount the provider + dashboard into the grafana container**

In the `grafana` container's `volumes` list (currently ending with the
`grafana_admin_password` secret mount), add these two entries:

```nix
          "${grafanaDashboardsProvider}:/etc/grafana/provisioning/dashboards/dashboards.yaml:ro"
          "${./grafana-dashboards/system-performance.json}:/etc/grafana/provisioning/dashboards/json/system-performance.json:ro"
```

- [ ] **Step 3: Enable anonymous Viewer in the grafana container `environments`**

In the `grafana` container's `environments` attrset (currently has
`GF_SERVER_ROOT_URL`, `GF_SERVER_DOMAIN`, `GF_SECURITY_ADMIN_PASSWORD__FILE`,
`GF_USERS_ALLOW_SIGN_UP`), add:

```nix
          GF_AUTH_ANONYMOUS_ENABLED = "true";
          GF_AUTH_ANONYMOUS_ORG_ROLE = "Viewer";
          GF_AUTH_ANONYMOUS_HIDE_VERSION = "true";
```

Leave `GF_SERVER_ROOT_URL` and `GF_SERVER_DOMAIN` unchanged.

- [ ] **Step 4: Build**

Run: `cd ~/homelab && nixos-rebuild build --flake .#homeserver`
Expected: builds to completion (`Done. The new configuration is /nix/store/...`).

- [ ] **Step 5: Commit**

```bash
cd ~/homelab
git add services/observability.nix
git commit -m "feat(observability): provision system-perf dashboard + anonymous Viewer"
```

---

### Task 3: nginx — apex vhost + tinyauth on both Grafana doors

**Files:**
- Modify: `services/observability.nix` (the `services.nginx.virtualHosts."grafana.tigor.web.id"` block at the end of the file)

**Interfaces:**
- Consumes: anonymous Grafana + `system-perf` dashboard (Task 2); the `tinyauth` per-vhost option from `services/auth.nix`.
- Produces: `tigor.web.id` kiosk entry + gated `grafana.tigor.web.id`.

- [ ] **Step 1: Replace the grafana vhost block with two gated vhosts**

In `services/observability.nix`, replace the existing final block:

```nix
  # Grafana keeps its own login (admin password from sops); no tinyauth gate.
  services.nginx.virtualHosts."grafana.tigor.web.id" = {
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:${toString grafanaHostPort}";
  };
```

with:

```nix
  # Two doors to the same Grafana. Anonymous access is instance-wide (Task 2),
  # so BOTH vhosts are tinyauth-gated — nothing is world-readable.
  #
  # grafana.tigor.web.id — full Grafana (admin login for edits, Viewer otherwise).
  services.nginx.virtualHosts."grafana.tigor.web.id" = {
    forceSSL = true;
    tinyauth.enable = true;
    locations."/".proxyPass = "http://127.0.0.1:${toString grafanaHostPort}";
  };

  # tigor.web.id (apex) — read-only at-a-glance kiosk. Bare `/` redirects to the
  # system-perf dashboard in kiosk mode; everything else proxies Grafana so the
  # page is same-origin (root-relative API/asset calls work without CORS).
  services.nginx.virtualHosts."tigor.web.id" = {
    forceSSL = true;
    tinyauth.enable = true;
    locations."= /".extraConfig = ''
      return 302 /d/system-perf/system-performance?kiosk&theme=dark;
    '';
    locations."/".proxyPass = "http://127.0.0.1:${toString grafanaHostPort}";
  };
```

- [ ] **Step 2: Build**

Run: `cd ~/homelab && nixos-rebuild build --flake .#homeserver`
Expected: builds to completion. (The apex vhost inherits `useACMEHost = "tigor.web.id"` by default; the existing cert already has the apex as CN, so no new ACME wait.)

- [ ] **Step 3: Commit**

```bash
cd ~/homelab
git add services/observability.nix
git commit -m "feat(observability): apex tigor.web.id kiosk vhost + tinyauth on both"
```

---

### Task 4: Post-switch live verification (manual — after the user switches)

> NOT a build task. The user runs `sudo nixos-rebuild switch --flake ~/homelab#homeserver` from a real TTY, then verifies. Document outcomes; do not push fixes blindly.

- [ ] **Step 1:** From a fresh browser/phone, open `https://tigor.web.id` → tinyauth passkey prompt appears → after auth, lands on the kiosk dashboard (no Grafana menus/nav), address bar stays `tigor.web.id`.
- [ ] **Step 2:** Confirm panels render DATA (CPU/RAM/load/disk/net/uptime) — this proves the same-origin assumption. CPU-temp panel empty/"No data" is acceptable.
- [ ] **Step 3:** Open `https://grafana.tigor.web.id` → tinyauth → full Grafana loads; admin login still works for editing.
- [ ] **Step 4:** Confirm neither host loads Grafana without passing tinyauth first (no world-readable Grafana).
- [ ] **Step 5:** If panels show "No data" for everything (not just temp): same-origin assumption failed → fall back to setting `GF_SERVER_ROOT_URL`/`GF_SERVER_DOMAIN` to `tigor.web.id` and drop/redirect the subdomain. Report before changing.

---

## Self-Review

**Spec coverage:**
- Anonymous Viewer → Task 2 Step 3. Dashboard provisioning + JSON → Tasks 1, 2. Apex kiosk redirect + proxy → Task 3. tinyauth on both vhosts → Task 3. `root_url` unchanged → Global Constraints + Task 2 Step 3. No new exporter / node_* metrics → Task 1 queries. Acceptance criteria → Task 4. All spec sections covered.

**Placeholder scan:** none — full JSON + full nix snippets + exact commands.

**Type/name consistency:** dashboard uid `system-perf` consistent across Task 1 (JSON), Task 3 (redirect path `/d/system-perf/system-performance`); datasource uid `prometheus` matches existing `grafanaDatasources`; `grafanaHostPort` is the existing binding reused in Task 3.
