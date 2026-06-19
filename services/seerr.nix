# Seerr — media request manager (https://github.com/seerr-team/seerr, the
# Jellyseerr successor). Companion to the arr stack + jellyfin: users request
# movies/series, seerr forwards to radarr/sonarr and checks availability against
# jellyfin. Has its own login (Jellyfin auth) → NOT behind tinyauth, like
# jellyfin/immich. Joins the `arr` network to reach sonarr/radarr/jellyfin by
# name (see .claude/rules/container-networking.md). SQLite in /app/config (no
# external DB needed).
{
  homelab.containers.seerr = {
    image = "ghcr.io/seerr-team/seerr:latest";
    port = 5055;
    uid = 1000;
    user = "1000:1000"; # image defaults to root → force srv-mapped uid so /app/config lands as srv
    networks = [ "arr" ];
    volumes = [ "/var/mnt/state/seerr:/app/config" ];
    environments = {
      TZ = "Asia/Jakarta";
      LOG_LEVEL = "info";
    };
    tmpfiles = [ "d /var/mnt/state/seerr 0750 srv media -" ];
  };
}
