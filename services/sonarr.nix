# Sonarr — TV series management. linuxserver s6 image (harden=false + PUID/PGID).
# Mounts the whole /var/mnt/wolf tree as /data so downloads (/data/torrents) and the
# library (/data/media/tv) share one filesystem → atomic moves + hardlinks.
{
  homelab.containers.sonarr = {
    image = "lscr.io/linuxserver/sonarr:latest";
    port = 8989;
    auth = true;
    uid = 1000;
    harden = false;
    volumes = [
      "/var/mnt/state/sonarr:/config"
      "/var/mnt/wolf:/data"
    ];
    environments = {
      TZ = "Asia/Jakarta";
      PUID = "1000";
      PGID = "1000";
      UMASK = "002";
    };
    tmpfiles = [ "d /var/mnt/state/sonarr 0750 srv media -" ];
  };
  # qbittorrent saves arr categories to /data/torrents (wolf); Sonarr sees the
  # same files at /data/torrents and hardlinks imports into /data/media/tv. Paths
  # match the old deploy → carried configs need no Remote Path Mapping.
}
