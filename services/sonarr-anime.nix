# Sonarr (anime) — second Sonarr instance dedicated to anime, carried over from
# the old deploy's `sonarr-anime`. Identical to sonarr.nix but its own config dir,
# port, and vhost. Shares the same /data mount so its library (/data/media/anime)
# and downloads (/data/torrents) hardlink like the primary instance.
{
  homelab.containers.sonarr-anime = {
    image = "lscr.io/linuxserver/sonarr:latest";
    port = 8989; # in-container port (linuxserver default)
    hostPort = 8990; # host loopback (8989 = primary sonarr)
    subdomain = "sonarr-anime";
    auth = true;
    uid = 1000;
    harden = false;
    volumes = [
      "/var/mnt/state/sonarr-anime:/config"
      "/var/mnt/wolf:/data"
    ];
    environments = {
      TZ = "Asia/Jakarta";
      PUID = "1000";
      PGID = "1000";
      UMASK = "002";
    };
    tmpfiles = [ "d /var/mnt/state/sonarr-anime 0750 srv media -" ];
  };
}
