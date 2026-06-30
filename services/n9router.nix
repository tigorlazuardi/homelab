# 9router — self-hosted OpenAI-compatible AI proxy (decolua/9router): fronts 40+ LLM
# providers with auto-fallback. Coding tools point here instead of each provider.
# Public vhost; dashboard gated by n9router native OIDC (→ dex static client "9router",
# configured in the n9router UI at runtime); proxy API gated by API key
# (REQUIRE_API_KEY). sqlite db on state tier.
#
# The image's /entrypoint.sh does `chown … && su-exec node`, but su-exec's setgroups()
# is denied in this rootless userns (NixOS newgidmap isn't setuid → setgroups=deny),
# crashing the container with "su-exec: setgroups: Operation not permitted". Bypass it:
# run the real CMD (`node custom-server.js`) directly as uid 1000. keep-id maps 1000 →
# host srv, and /app + the mounted /app/data are already owned by 1000, so the
# entrypoint's chown is unnecessary. No privilege drop → harden stays on (default).
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
    user = "1000:1000"; # run as node directly (bypass su-exec; see header)
    extraContainerConfig = {
      entrypoint = "node"; # skip /entrypoint.sh (su-exec setgroups fails rootless)
      exec = "custom-server.js"; # image CMD; WorkingDir /app from image
      # OIDC discovery/token to dex happen server-side; rootless pasta can't hairpin
      # to the host's own public IP, so route dex.tigor.web.id to the host gateway —
      # nginx serves the dex vhost by Host header (same trick as tinyauth/dex).
      addHosts = [ "dex.tigor.web.id:host-gateway" ];
    };
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
