# Prowlarr — indexer manager for the *arr stack. linuxserver s6 image, so
# harden=false + PUID/PGID. No media mount (it only manages indexers); it reaches
# flaresolverr for Cloudflare-gated indexers at host.containers.internal:8191
# (configure the FlareSolverr proxy in the UI).
{
  homelab.containers.prowlarr = {
    image = "lscr.io/linuxserver/prowlarr:latest";
    port = 9696;
    networks = [ "arr" ];
    auth = true;
    uid = 1000;
    harden = false; # linuxserver s6 init needs caps
    volumes = [ "/var/mnt/state/prowlarr:/config" ];
    environments = {
      TZ = "Asia/Jakarta";
      PUID = "1000";
      PGID = "1000";
      UMASK = "002";
    };
    tmpfiles = [ "d /var/mnt/state/prowlarr 0750 srv media -" ];
  };
}
