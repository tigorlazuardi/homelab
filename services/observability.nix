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
        metrics = [otelcol.processor.transform.env.input]
        logs    = [otelcol.processor.transform.env.input]
        traces  = [otelcol.processor.transform.env.input]
      }
    }

    // Stamp every signal's RESOURCE with the deployment environment (single-host
    // homelab → value is the homeserver username). Set both the new semconv key
    // and the legacy one. (Alloy v1.14 has no otelcol.processor.resource, so use
    // transform with the resource context.)
    otelcol.processor.transform "env" {
      error_mode = "ignore"
      trace_statements {
        context    = "resource"
        statements = [
          `set(attributes["deployment.environment.name"], "homeserver")`,
          `set(attributes["deployment.environment"], "homeserver")`,
        ]
      }
      metric_statements {
        context    = "resource"
        statements = [
          `set(attributes["deployment.environment.name"], "homeserver")`,
          `set(attributes["deployment.environment"], "homeserver")`,
        ]
      }
      // Promote service.name + deployment.environment[.name] onto each metric
      // DATAPOINT — otelcol.exporter.prometheus turns datapoint attributes into
      // labels (resource attributes only land in target_info, forcing a join).
      // This is the equivalent of Mimir's promote_resource_attributes, but
      // selective (only the two keys we want as labels). Runs after the resource
      // block above, so the env values are already set.
      metric_statements {
        context    = "datapoint"
        statements = [
          `set(attributes["service.name"], resource.attributes["service.name"]) where resource.attributes["service.name"] != nil`,
          `set(attributes["service.namespace"], resource.attributes["service.namespace"]) where resource.attributes["service.namespace"] != nil`,
          `set(attributes["deployment.environment.name"], resource.attributes["deployment.environment.name"])`,
          `set(attributes["deployment.environment"], resource.attributes["deployment.environment"])`,
        ]
      }
      log_statements {
        context    = "resource"
        statements = [
          `set(attributes["deployment.environment.name"], "homeserver")`,
          `set(attributes["deployment.environment"], "homeserver")`,
        ]
      }
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
      // metric-label form of deployment.environment.name (dots → underscores).
      // Covers both host-scraped and OTLP-converted metrics uniformly.
      external_labels = {
        deployment_environment_name = "homeserver",
      }
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

    // Rootless quadlet containers run as systemd *user* units under srv and log
    // to the journal (Quadlet's default passthrough driver), so reading the whole
    // journal already captures podman container output. Relabel surfaces the unit
    // / container name so container logs are queryable per service in Loki.
    loki.relabel "journal" {
      forward_to = []
      // system unit (host services)
      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
      }
      // user unit (rootless containers) overrides when present
      rule {
        source_labels = ["__journal__systemd_user_unit"]
        regex         = "(.+)"
        target_label  = "unit"
      }
      // podman journald driver, if enabled on a container
      rule {
        source_labels = ["__journal_container_name"]
        regex         = "(.+)"
        target_label  = "container"
      }
      // service.name = the unit name (copy the resolved `unit` label).
      rule {
        source_labels = ["unit"]
        target_label  = "service_name"
      }
    }

    loki.source.journal "host" {
      forward_to    = [loki.write.default.receiver]
      relabel_rules = loki.relabel.journal.rules
      labels        = {
        job                         = "systemd-journal",
        host                        = "homeserver",
        deployment_environment_name = "homeserver",
      }
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
          "/var/mnt/state/prometheus:/prometheus"
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
          "/var/mnt/state/loki:/loki"
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
        # Pinned: tempo:latest rejects the standard `compactor` config field
        # ("field compactor not found in type app.Config"). 2.6.1 is known-good.
        image = "docker.io/grafana/tempo:2.6.1";
        userns = "keep-id:uid=10001,gid=10001";
        publishPorts = [
          "127.0.0.1:${toString tempoHttpPort}:${toString tempoHttpPort}"
          "127.0.0.1:${toString tempoOtlpHostPort}:4317"
        ];
        volumes = [
          "${tempoYml}:/etc/tempo/tempo.yml:ro"
          "/var/mnt/state/tempo:/var/tempo"
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
          "/var/mnt/state/grafana:/var/lib/grafana"
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
    "d /var/mnt/state/prometheus 0750 srv srv -"
    "d /var/mnt/state/loki 0750 srv srv -"
    "d /var/mnt/state/tempo 0750 srv srv -"
    "d /var/mnt/state/grafana 0750 srv srv -"
  ];

  # Grafana keeps its own login (admin password from sops); no tinyauth gate.
  services.nginx.virtualHosts."grafana.tigor.web.id" = {
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:${toString grafanaHostPort}";
  };
}
