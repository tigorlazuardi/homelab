# Bazarr — subtitle management for Sonarr/Radarr. linuxserver s6 image
# (harden=false + PUID/PGID). Mounts /data so its media paths match Sonarr's and
# Radarr's (/data/media/tv, /data/media/movies) and subtitles land beside media.
{
  homelab.containers.bazarr = {
    image = "lscr.io/linuxserver/bazarr:latest";
    port = 6767;
    auth = true;
    uid = 1000;
    harden = false;
    volumes = [
      "/srv/data/state/bazarr:/config"
      "/srv/data:/data"
    ];
    environments = {
      TZ = "Asia/Jakarta";
      PUID = "1000";
      PGID = "1000";
      UMASK = "002";
    };
    tmpfiles = [ "d /srv/data/state/bazarr 0750 srv media -" ];
  };
}
