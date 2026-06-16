# Paperless-ngx — document management. Multi-container (app + redis) on a private
# rootless network, so explicit (not the single-container helper). Scanned docs
# are personal data → /srv/data owned srv:media.
{ config, ... }:
let
  domain = "docs.tigor.web.id";
  # Captured from the SYSTEM config (the inner home-manager block shadows `config`).
  envPath = config.sops.secrets."paperless-ngx.env".path;
in
{
  sops.secrets."paperless-ngx.env" = {
    sopsFile = ../secrets/paperless-ngx.env;
    format = "dotenv";
    key = "";
    owner = "srv"; # rootless container (srv user) must read it
  };

  home-manager.users.srv =
    { config, ... }:
    let
      inherit (config.virtualisation.quadlet) networks;
    in
    {
      virtualisation.quadlet = {
        networks.paperless = { };

        containers.paperless-ngx = {
          autoStart = true;
          containerConfig = {
            image = "ghcr.io/paperless-ngx/paperless-ngx:latest";
            publishPorts = [ "127.0.0.1:8000:8000" ];
            networks = [ networks.paperless.ref ];
            # Official image inits as root then drops to USERMAP_UID via gosu →
            # keep-id maps that to host srv. Not cap-dropped (init needs CHOWN).
            userns = "keep-id:uid=1000,gid=1000";
            volumes = [
              "/srv/data/state/paperless/data:/usr/src/paperless/data"
              "/srv/data/state/paperless/media:/usr/src/paperless/media"
              "/srv/data/state/paperless/export:/usr/src/paperless/export"
              "/srv/data/state/paperless/consume:/usr/src/paperless/consume"
            ];
            environments = {
              PAPERLESS_REDIS = "redis://paperless-redis:6379";
              USERMAP_UID = "1000";
              USERMAP_GID = "1000";
              PAPERLESS_URL = "https://${domain}";
              PAPERLESS_TIME_ZONE = "Asia/Jakarta";
              PAPERLESS_OCR_LANGUAGE = "ind";
              PAPERLESS_OCR_LANGUAGES = "ind";
              PAPERLESS_USE_X_FORWARD_HOST = "true";
              PAPERLESS_USE_X_FORWARD_PORT = "true";
              PAPERLESS_PROXY_SSL_HEADER = ''["HTTP_X_FORWARDED_PROTO", "https"]'';
              PAPERLESS_ALLOWED_HOSTS = domain;
              PAPERLESS_CSRF_TRUSTED_ORIGINS = "https://${domain}";
              PAPERLESS_CORS_ALLOWED_HOSTS = "https://${domain}";
            };
            environmentFiles = [ envPath ];
            autoUpdate = "registry";
          };
        };

        containers.paperless-redis = {
          autoStart = true;
          containerConfig = {
            image = "docker.io/library/redis:8";
            networks = [ networks.paperless.ref ];
            userns = null; # run as root-in-userns → host srv (writes its data dir)
            volumes = [ "/srv/data/state/paperless/redis:/data" ];
            noNewPrivileges = true;
            dropCapabilities = [ "all" ];
            autoUpdate = "registry";
          };
        };
      };
    };

  systemd.tmpfiles.rules = [
    "d /srv/data/state/paperless 0750 srv srv -"
    "d /srv/data/state/paperless/data 2775 srv media -"
    "d /srv/data/state/paperless/media 2775 srv media -"
    "d /srv/data/state/paperless/export 2775 srv media -"
    "d /srv/data/state/paperless/consume 2775 srv media -"
    "d /srv/data/state/paperless/redis 0750 srv srv -"
  ];

  services.nginx.virtualHosts."${domain}" = {
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:8000";
  };
}
