# Observability — Grafana LGTM-ish stack (no Mimir; Prometheus for metrics).
#
# Topology:
#   apps ──OTLP─┐
#               ▼
#   Alloy (NATIVE on host: also collects host node metrics + journald logs;
#          reads the real /proc — a container would only see its own netns)
#     ├─ metrics ─► Prometheus  (remote-write receiver)
#     ├─ logs    ─► Loki
#     └─ traces  ─► Tempo
#                     ▼
#                  Grafana (provisioned datasources + Telegram alerting)
#
# Alloy is native because host metrics need host /proc + /sys (the same reason
# the old SigNoz setup ran a separate host collector). Everything else is a
# rootless container published to loopback; Alloy and Grafana reach them via
# 127.0.0.1 / host.containers.internal. Grafana is the only public vhost.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  yaml = pkgs.formats.yaml { };

  # ---- host-loopback ports (containers publish here) ----
  promPort = 9090;
  lokiPort = 3100;
  tempoHttpPort = 3200;
  tempoOtlpHostPort = 4319; # → container 4317 (avoids clashing with Alloy 4317)
  grafanaHostPort = 3300; # → container 3000

  retentionHours = "360h"; # 15 days

  prometheusYml = yaml.generate "prometheus.yml" {
    global.scrape_interval = "15s";
  };

  lokiYml = yaml.generate "loki.yml" {
    auth_enabled = false;
    server.http_listen_port = lokiPort;
    common = {
      instance_addr = "127.0.0.1";
      path_prefix = "/loki";
      storage.filesystem = {
        chunks_directory = "/loki/chunks";
        rules_directory = "/loki/rules";
      };
      replication_factor = 1;
      ring.kvstore.store = "inmemory";
    };
    schema_config.configs = [
      {
        from = "2024-01-01";
        store = "tsdb";
        object_store = "filesystem";
        schema = "v13";
        index = {
          prefix = "index_";
          period = "24h";
        };
      }
    ];
    limits_config.retention_period = retentionHours;
    compactor = {
      working_directory = "/loki/compactor";
      retention_enabled = true;
      delete_request_store = "filesystem";
    };
  };

  tempoYml = yaml.generate "tempo.yml" {
    server.http_listen_port = tempoHttpPort;
    distributor.receivers.otlp.protocols.grpc.endpoint = "0.0.0.0:4317";
    storage.trace = {
      backend = "local";
      local.path = "/var/tempo/traces";
      wal.path = "/var/tempo/wal";
    };
    compactor.compaction.block_retention = retentionHours;
  };

  grafanaDatasources = yaml.generate "datasources.yaml" {
    apiVersion = 1;
    datasources = [
      {
        name = "Prometheus";
        type = "prometheus";
        uid = "prometheus";
        access = "proxy";
        url = "http://host.containers.internal:${toString promPort}";
        isDefault = true;
      }
      {
        name = "Loki";
        type = "loki";
        uid = "loki";
        access = "proxy";
        url = "http://host.containers.internal:${toString lokiPort}";
      }
      {
        name = "Tempo";
        type = "tempo";
        uid = "tempo";
        access = "proxy";
        url = "http://host.containers.internal:${toString tempoHttpPort}";
      }
    ];
  };

  # Native Alloy: OTLP gateway + host node metrics + journald.
  alloyConfig = pkgs.writeText "config.alloy" ''
    // ---- OTLP ingestion (apps) ----
    otelcol.receiver.otlp "in" {
      grpc { endpoint = "0.0.0.0:4317" }
      http { endpoint = "0.0.0.0:4318" }
      output {
        metrics = [otelcol.processor.batch.default.input]
        logs    = [otelcol.processor.batch.default.input]
        traces  = [otelcol.processor.batch.default.input]
      }
    }

    otelcol.processor.batch "default" {
      output {
        metrics = [otelcol.exporter.prometheus.default.input]
        logs    = [otelcol.exporter.loki.default.input]
        traces  = [otelcol.exporter.otlp.tempo.input]
      }
    }

    // ---- fan-out to backends (loopback) ----
    otelcol.exporter.prometheus "default" {
      forward_to = [prometheus.remote_write.default.receiver]
    }
    prometheus.remote_write "default" {
      endpoint { url = "http://127.0.0.1:${toString promPort}/api/v1/write" }
    }

    otelcol.exporter.loki "default" {
      forward_to = [loki.write.default.receiver]
    }
    loki.write "default" {
      endpoint { url = "http://127.0.0.1:${toString lokiPort}/loki/api/v1/push" }
    }

    otelcol.exporter.otlp "tempo" {
      client {
        endpoint = "127.0.0.1:${toString tempoOtlpHostPort}"
        tls { insecure = true }
      }
    }

    // ---- host telemetry (real /proc, /sys, journald) ----
    prometheus.exporter.unix "host" { }
    prometheus.scrape "host" {
      targets         = prometheus.exporter.unix.host.targets
      forward_to      = [prometheus.remote_write.default.receiver]
      scrape_interval = "15s"
    }

    loki.source.journal "host" {
      forward_to = [loki.write.default.receiver]
      labels     = { job = "systemd-journal", host = "homeserver" }
    }
  '';
in
{
  # ---- secrets (owner srv: read by the Grafana container) ----
  sops.secrets = {
    "observability/grafana_admin_password" = {
      sopsFile = ../secrets/observability.yaml;
      key = "grafana_admin_password";
      owner = "srv";
    };
    # Reuse the smartd Telegram bot for Grafana alerts (separate entry so it can
    # be srv-owned without touching the root-owned smartd secret).
    "observability/telegram_bot_token" = {
      sopsFile = ../secrets/smartd.yaml;
      key = "telegram_bot_token";
      owner = "srv";
    };
    "observability/telegram_chat_id" = {
      sopsFile = ../secrets/smartd.yaml;
      key = "telegram_chat_id";
      owner = "srv";
    };
  };

  # Grafana alerting provisioning rendered with the Telegram secret.
  sops.templates."grafana-telegram.yaml" = {
    owner = "srv";
    content = builtins.toJSON {
      apiVersion = 1;
      contactPoints = [
        {
          orgId = 1;
          name = "telegram";
          receivers = [
            {
              uid = "telegram";
              type = "telegram";
              settings = {
                bottoken = config.sops.placeholder."observability/telegram_bot_token";
                chatid = config.sops.placeholder."observability/telegram_chat_id";
              };
            }
          ];
        }
      ];
      policies = [
        {
          orgId = 1;
          receiver = "telegram";
        }
      ];
    };
  };

  # ---- native Alloy ----
  environment.etc."alloy/config.alloy".source = alloyConfig;
  services.alloy.enable = true;

  # LAN telemetry senders (behind the home router; no WAN exposure).
  networking.firewall.allowedTCPPorts = [
    4317
    4318
  ];

  # ---- backend containers (rootless srv, loopback only) ----
  home-manager.users.srv.virtualisation.quadlet.containers = {
    prometheus = {
      autoStart = true;
      containerConfig = {
        image = "docker.io/prom/prometheus:latest";
        userns = "keep-id:uid=65534,gid=65534"; # prom image runs as nobody
        publishPorts = [ "127.0.0.1:${toString promPort}:9090" ];
        volumes = [
          "${prometheusYml}:/etc/prometheus/prometheus.yml:ro"
          "/srv/data/state/prometheus:/prometheus"
        ];
        exec = "--config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/prometheus --storage.tsdb.retention.time=30d --web.enable-remote-write-receiver --web.enable-otlp-receiver --web.listen-address=0.0.0.0:9090";
        noNewPrivileges = true;
        dropCapabilities = [ "all" ];
        autoUpdate = "registry";
      };
    };

    loki = {
      autoStart = true;
      containerConfig = {
        image = "docker.io/grafana/loki:latest";
        userns = "keep-id:uid=10001,gid=10001";
        publishPorts = [ "127.0.0.1:${toString lokiPort}:${toString lokiPort}" ];
        volumes = [
          "${lokiYml}:/etc/loki/loki.yml:ro"
          "/srv/data/state/loki:/loki"
        ];
        exec = "-config.file=/etc/loki/loki.yml";
        noNewPrivileges = true;
        dropCapabilities = [ "all" ];
        autoUpdate = "registry";
      };
    };

    tempo = {
      autoStart = true;
      containerConfig = {
        image = "docker.io/grafana/tempo:latest";
        userns = "keep-id:uid=10001,gid=10001";
        publishPorts = [
          "127.0.0.1:${toString tempoHttpPort}:${toString tempoHttpPort}"
          "127.0.0.1:${toString tempoOtlpHostPort}:4317"
        ];
        volumes = [
          "${tempoYml}:/etc/tempo/tempo.yml:ro"
          "/srv/data/state/tempo:/var/tempo"
        ];
        exec = "-config.file=/etc/tempo/tempo.yml";
        noNewPrivileges = true;
        dropCapabilities = [ "all" ];
        autoUpdate = "registry";
      };
    };

    grafana = {
      autoStart = true;
      containerConfig = {
        image = "docker.io/grafana/grafana:latest";
        userns = "keep-id:uid=472,gid=472"; # grafana image runs as uid 472
        publishPorts = [ "127.0.0.1:${toString grafanaHostPort}:3000" ];
        volumes = [
          "/srv/data/state/grafana:/var/lib/grafana"
          "${grafanaDatasources}:/etc/grafana/provisioning/datasources/datasources.yaml:ro"
          "${config.sops.templates."grafana-telegram.yaml".path}:/etc/grafana/provisioning/alerting/telegram.yaml:ro"
          "${config.sops.secrets."observability/grafana_admin_password".path}:/run/secrets/grafana_admin_password:ro"
        ];
        environments = {
          GF_SERVER_ROOT_URL = "https://grafana.tigor.web.id";
          GF_SERVER_DOMAIN = "grafana.tigor.web.id";
          GF_SECURITY_ADMIN_PASSWORD__FILE = "/run/secrets/grafana_admin_password";
          GF_USERS_ALLOW_SIGN_UP = "false";
        };
        noNewPrivileges = true;
        dropCapabilities = [ "all" ];
        autoUpdate = "registry";
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /srv/data/state/prometheus 0750 srv srv -"
    "d /srv/data/state/loki 0750 srv srv -"
    "d /srv/data/state/tempo 0750 srv srv -"
    "d /srv/data/state/grafana 0750 srv srv -"
  ];

  # Grafana keeps its own login (admin password from sops); no tinyauth gate.
  services.nginx.virtualHosts."grafana.tigor.web.id" = {
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:${toString grafanaHostPort}";
  };
}
