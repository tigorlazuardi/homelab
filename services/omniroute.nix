# OmniRoute — self-hosted free AI gateway (diegosouzapw/OmniRoute): one OpenAI-
# compatible endpoint fronting 200+ LLM providers with auto-fallback + token
# compression. Replaces the removed 9router. Private vhost: LAN + wireguard VPN
# only (no auth gate, no API key — access is controlled purely at nginx). sqlite
# state on the state tier; redis is optional (QUOTA_STORE_DRIVER=sqlite) so this
# runs single-container.
#
# The image runs as USER node (uid 1000) with a plain permission-check entrypoint
# that execs `node dev/run-standalone.mjs` — no su-exec/setgroups privilege drop,
# so (unlike n9router) it needs no entrypoint bypass and hardening stays on.
# keep-id maps uid 1000 -> host srv. Required secrets (JWT/API-key/storage-enc/
# ws-bridge/initial-password) come from the sops env file; the rest is plain env.
{ config, ... }:
{
  sops.secrets."omniroute.env" = {
    sopsFile = ../secrets/omniroute.env;
    format = "dotenv";
    key = "";
    owner = "srv";
  };
  homelab.containers.omniroute = {
    image = "docker.io/diegosouzapw/omniroute:latest";
    autoUpdate = "registry"; # track latest provider/model support (private vhost, same call as 9router)
    port = 20128;
    subdomain = "omniroute";
    uid = 1000; # node user -> keep-id -> host srv
    volumes = [ "/var/mnt/state/omniroute:/app/data" ];
    environments = {
      TZ = "Asia/Jakarta";
      NODE_ENV = "production";
      DATA_DIR = "/app/data";
      PORT = "20128";
      HOSTNAME = "0.0.0.0";
      QUOTA_STORE_DRIVER = "sqlite"; # single-container; no redis sidecar
      REQUIRE_API_KEY = "false"; # no API gate — private network only
      AUTH_COOKIE_SECURE = "true"; # served over https
      STORAGE_ENCRYPTION_KEY_VERSION = "v1";
      BASE_URL = "https://omniroute.tigor.web.id";
      NEXT_PUBLIC_BASE_URL = "https://omniroute.tigor.web.id";
    };
    environmentFiles = [ config.sops.secrets."omniroute.env".path ];
    # Private vhost: LAN + wireguard VPN only, no internet exposure, no auth gate.
    nginx.extraConfig = ''
      allow 192.168.100.0/24;  # LAN
      allow 10.0.0.0/24;       # wireguard VPN
      allow 127.0.0.1;
      deny all;
    '';
    tmpfiles = [ "d /var/mnt/state/omniroute 0750 srv srv -" ];
  };
}
