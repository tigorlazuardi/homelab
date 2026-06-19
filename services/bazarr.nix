# Bazarr — subtitle management for Sonarr/Radarr. linuxserver s6 image
# (harden=false + PUID/PGID). Mounts /data so its media paths match Sonarr's and
# Radarr's (/data/media/tv, /data/media/movies) and subtitles land beside media.
{
  homelab.containers.bazarr = {
    image = "lscr.io/linuxserver/bazarr:latest";
    port = 6767;
    networks = [ "arr" ];
    auth = true;
    uid = 1000;
    harden = false;
    volumes = [
      "/var/mnt/state/bazarr:/config"
      "/var/mnt/wolf:/data"
    ];
    environments = {
      TZ = "Asia/Jakarta";
      PUID = "1000";
      PGID = "1000";
      UMASK = "002";
    };
    tmpfiles = [ "d /var/mnt/state/bazarr 0750 srv media -" ];
  };
}
