# 9router — self-hosted OpenAI-compatible AI proxy (decolua/9router): fronts 40+ LLM
# providers with auto-fallback. Coding tools point here instead of each provider.
# Public vhost; dashboard gated by n9router native OIDC (→ dex static client "9router",
# configured in the n9router UI at runtime); proxy API gated by API key
# (REQUIRE_API_KEY). Entrypoint runs as root → chown -R node:node /app/data → su-exec
# node (uid 1000); needs caps, so harden = false. sqlite db on state tier.
{ config, ... }:
{
  sops.secrets."n9router.env" = {
    sopsFile = ../secrets/n9router.env;
    format = "dotenv";
    key = "";
    owner = "srv";
  };
  homelab.containers.n9router = {
    image = "ghcr.io/decolua/9router:latest";
    autoUpdate = "registry"; # track latest LLM-model support (user override of digest-pin)
    port = 20128;
    subdomain = "9router";
    uid = 1000; # node user → keep-id → host srv
    harden = false; # entrypoint chowns + su-exec node; needs CHOWN/SETUID/SETGID
    volumes = [ "/var/mnt/state/n9router:/app/data" ];
    environments = {
      TZ = "Asia/Jakarta";
      DATA_DIR = "/app/data";
      NODE_ENV = "production";
      PORT = "20128";
      NEXT_PUBLIC_BASE_URL = "https://9router.tigor.web.id";
      BASE_URL = "https://9router.tigor.web.id";
      AUTH_COOKIE_SECURE = "true";
      OBSERVABILITY_ENABLED = "true";
      REQUIRE_API_KEY = "true";
    };
    environmentFiles = [ config.sops.secrets."n9router.env".path ];
    tmpfiles = [ "d /var/mnt/state/n9router 0750 srv srv -" ];
  };
}
