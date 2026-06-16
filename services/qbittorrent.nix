# qBittorrent — THE hostile tenant (untrusted torrents). linuxserver s6 image, so
# it can't be fully hardened (s6 init needs caps); compensate with: downloads-only
# write scope, loopback web UI, future auth gate + resource caps. keep-id:uid=1000
# → files land as srv:media. BT peer ports are the only 0.0.0.0 exposure.
{ pkgs, ... }:
{
  homelab.containers.qbittorrent = {
    image = "docker.io/linuxserver/qbittorrent:latest";
    port = 8080;
    hostPort = 8083; # host 8080 is searxng
    auth = true;
    authLocations = [ "/" ]; # gate the UI only; leave the API reachable
    uid = 1000;
    harden = false; # linuxserver s6 needs CHOWN/SETUID/SETGID
    volumes = [
      "/var/mnt/state/qbittorrent:/config"
      # Personal/manual downloads → nas (disposable, dying disk).
      "/var/mnt/nas/downloads:/downloads"
      # arr-category downloads → wolf, SAME container path the *arr stack sees
      # (/data/torrents) so imports hardlink into /data/media on wolf. Path name
      # matches the OLD deploy so carried qbit fastresume + arr configs need no
      # edits and seeding resumes in place.
      "/var/mnt/wolf/torrents:/data/torrents"
      "${pkgs.vuetorrent}/share/vuetorrent:/webui/vuetorrent:ro"
    ];
    environments = {
      TZ = "Asia/Jakarta";
      PUID = "1000";
      PGID = "1000";
      UMASK = "002";
      WEBUI_PORT = "8080";
    };
    # BitTorrent peer port — must be reachable (not loopback).
    extraContainerConfig.publishPorts = [
      "6881:6881"
      "6881:6881/udp"
    ];
    tmpfiles = [ "d /var/mnt/state/qbittorrent 0750 srv media -" ];
  };

  networking.firewall.allowedTCPPorts = [ 6881 ];
  networking.firewall.allowedUDPPorts = [ 6881 ];
  # TODO(cutover): add CPU/IO resource caps via the container's serviceConfig.
  # Carried qbit config already has: default save /downloads (nas) and category
  # save paths (sonarr/radarr/anime) → /data/torrents (wolf). Paths match the old
  # deploy, so no UI changes needed at cutover.
}
