# Navidrome — music server. Reader: music mounted :ro.
{
  homelab.containers.navidrome = {
    image = "docker.io/deluan/navidrome:latest"; # FQ — autoUpdate needs it
    port = 4533;
    uid = 1000;
    user = "1000:1000";
    volumes = [
      "/var/mnt/state/navidrome:/data"
      "/var/mnt/wolf/media/music:/music:ro"
    ];
    environments = {
      TZ = "Asia/Jakarta";
      ND_SCANSCHEDULE = "1h";
      ND_LOGLEVEL = "info";
      ND_SESSIONTIMEOUT = "24h";
      ND_BASEURL = "";
    };
    tmpfiles = [ "d /var/mnt/state/navidrome 0750 srv srv -" ];
  };
}
