# FlareSolverr — Cloudflare-challenge solver. Stateless pilot service.
{
  homelab.containers.flaresolverr = {
    image = "ghcr.io/flaresolverr/flaresolverr:latest";
    port = 8191;
    environments = {
      TZ = "Asia/Jakarta";
      LOG_LEVEL = "info";
    };
  };
}
