# Navidrome — music server. Reader: music mounted :ro.
{
  homelab.containers.navidrome = {
    image = "deluan/navidrome:latest";
    port = 4533;
    uid = 1000;
    user = "1000:1000";
    volumes = [
      "/srv/data/state/navidrome:/data"
      "/srv/data/media/music:/music:ro"
    ];
    environments = {
      TZ = "Asia/Jakarta";
      ND_SCANSCHEDULE = "1h";
      ND_LOGLEVEL = "info";
      ND_SESSIONTIMEOUT = "24h";
      ND_BASEURL = "";
    };
    tmpfiles = [ "d /srv/data/state/navidrome 0750 srv srv -" ];
  };
}
