# Recyclarr — syncs TRaSH-guide quality profiles / custom formats into Sonarr +
# Radarr on a schedule. No web UI (port=null → no nginx vhost). Runs the official
# image in cron mode (CRON_SCHEDULE). Config carried from the old deploy's
# servarr/recyclarr → /var/mnt/state/recyclarr.
#
# It reaches the *arr instances over the host loopback published ports via
# host.containers.internal (configure base_url in recyclarr.yml, see TODO).
{
  homelab.containers.recyclarr = {
    image = "ghcr.io/recyclarr/recyclarr:latest";
    port = null; # headless — no ingress
    uid = 1000; # match carried config ownership
    volumes = [ "/var/mnt/state/recyclarr:/config" ];
    environments = {
      TZ = "Asia/Jakarta";
      CRON_SCHEDULE = "0 4 * * *"; # nightly sync at 04:00
    };
    tmpfiles = [ "d /var/mnt/state/recyclarr 0750 srv media -" ];
  };
  # TODO(cutover): recyclarr.yml base_url for sonarr/radarr must point at
  # http://host.containers.internal:8989 / :7878 (+ :8990 sonarr-anime) and use
  # each instance's API key. Old config likely references old container IPs/names.
}
