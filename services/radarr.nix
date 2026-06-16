# Radarr — movie management. linuxserver s6 image (harden=false + PUID/PGID).
# Same /data mount as Sonarr so library (/data/media/movies) and downloads share
# a filesystem for hardlinks / atomic moves.
{
  homelab.containers.radarr = {
    image = "lscr.io/linuxserver/radarr:latest";
    port = 7878;
    auth = true;
    uid = 1000;
    harden = false;
    volumes = [
      "/srv/data/state/radarr:/config"
      "/srv/data:/data"
    ];
    environments = {
      TZ = "Asia/Jakarta";
      PUID = "1000";
      PGID = "1000";
      UMASK = "002";
    };
    tmpfiles = [ "d /srv/data/state/radarr 0750 srv media -" ];
  };
}
