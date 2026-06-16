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
    uid = 1000;
    harden = false; # linuxserver s6 needs CHOWN/SETUID/SETGID
    volumes = [
      "/srv/data/state/qbittorrent:/config"
      "/srv/data/downloads:/downloads"
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
    tmpfiles = [ "d /srv/data/state/qbittorrent 0750 srv media -" ];
  };

  networking.firewall.allowedTCPPorts = [ 6881 ];
  networking.firewall.allowedUDPPorts = [ 6881 ];
  # TODO(auth wave): gate the web UI; it stays loopback-only meanwhile.
  # TODO(cutover): add CPU/IO resource caps via the container's serviceConfig.
}
