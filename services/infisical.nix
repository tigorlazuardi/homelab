# Infisical — secrets manager for Cloudflare demo/MVP projects. Multi-container
# (postgres + redis + backend) on a private rootless network → explicit.
# Data loss is acceptable (disposable), so a fresh Postgres is fine.
{ config, ... }:
let
  domain = "infisical.tigor.web.id";
  envPath = config.sops.secrets."infisical.env".path;
in
{
  sops.secrets."infisical.env" = {
    sopsFile = ../secrets/infisical.env;
    format = "dotenv";
    key = "";
    owner = "srv";
  };

  home-manager.users.srv =
    { config, ... }:
    let
      inherit (config.virtualisation.quadlet) networks;
    in
    {
      virtualisation.quadlet = {
        networks.infisical = { };

        containers.infisical-postgres = {
          autoStart = true;
          containerConfig = {
            image = "docker.io/postgres:14-alpine";
            networks = [ networks.infisical.ref ];
            # alpine postgres runs as uid 70 — TODO(cutover): verify.
            userns = "keep-id:uid=70,gid=70";
            volumes = [ "/srv/data/state/infisical/postgres:/var/lib/postgresql/data" ];
            environments = {
              POSTGRES_USER = "infisical";
              POSTGRES_DB = "infisical";
            };
            environmentFiles = [ envPath ];
            healthCmd = "pg_isready -U infisical";
            autoUpdate = "registry";
          };
        };

        containers.infisical-redis = {
          autoStart = true;
          containerConfig = {
            image = "docker.io/redis:7-alpine";
            networks = [ networks.infisical.ref ];
            userns = null; # root-in-userns → host srv
            volumes = [ "/srv/data/state/infisical/redis:/data" ];
            environments.ALLOW_EMPTY_PASSWORD = "yes";
            healthCmd = "redis-cli ping";
            noNewPrivileges = true;
            dropCapabilities = [ "all" ];
            autoUpdate = "registry";
          };
        };

        containers.infisical-backend = {
          autoStart = true;
          containerConfig = {
            image = "docker.io/infisical/infisical:v0.159.19";
            publishPorts = [ "127.0.0.1:8084:8080" ];
            networks = [ networks.infisical.ref ];
            environments = {
              NODE_ENV = "production";
              SITE_URL = "https://${domain}";
              REDIS_URL = "redis://infisical-redis:6379";
              TELEMETRY_ENABLED = "false";
            };
            environmentFiles = [ envPath ];
            autoUpdate = "registry";
          };
        };
      };
    };

  systemd.tmpfiles.rules = [
    "d /srv/data/state/infisical 0750 srv srv -"
    "d /srv/data/state/infisical/postgres 0700 srv srv -"
    "d /srv/data/state/infisical/redis 0750 srv srv -"
  ];

  services.nginx.virtualHosts."${domain}" = {
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8084";
      extraConfig = ''
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
      '';
    };
  };

  # TODO(cutover): DB_CONNECTION_URI inside infisical.env points at the OLD
  # postgres IP (10.88.7.1). Update its host to `infisical-postgres` (decrypt with
  # `sops`, needs your permission). Backend crash-loops until then.
  # TODO(cutover): backend has no explicit ordering on pg/redis — relies on
  # restart-on-failure. Add unit ordering if startup is flaky.
}
