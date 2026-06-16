# Suwayomi — manga server. Single container, runs as uid 1000 inside.
# Reaches flaresolverr via the host's published loopback port.
{
  home-manager.users.srv.virtualisation.quadlet.containers.suwayomi = {
    autoStart = true;
    containerConfig = {
      image = "ghcr.io/suwayomi/suwayomi-server:stable";
      publishPorts = [ "127.0.0.1:4567:4567" ];
      userns = "keep-id:uid=1000,gid=1000";
      volumes = [
        "/srv/data/state/suwayomi:/home/suwayomi/.local/share/Tachidesk"
        "/srv/data/media/manga:/home/suwayomi/.local/share/Tachidesk/downloads"
      ];
      environments = {
        TZ = "Asia/Jakarta";
        AUTO_DOWNLOAD_CHAPTERS = "true";
        AUTO_DOWNLOAD_EXCLUDE_UNREAD = "false";
        MAX_SOURCES_IN_PARALLEL = "20";
        UPDATE_EXCLUDE_UNREAD = "false";
        UPDATE_EXCLUDE_STARTED = "false";
        FLARESOLVERR_ENABLED = "true";
        # rootless: reach flaresolverr's host-published port (own netns can't see
        # the other container's loopback directly).
        FLARESOLVERR_URL = "http://host.containers.internal:8191";
      };
      noNewPrivileges = true;
      dropCapabilities = [ "all" ];
      autoUpdate = "registry";
    };
  };

  systemd.tmpfiles.rules = [
    "d /srv/data/state/suwayomi 0750 srv srv -"
    "d /srv/data/media/manga 2775 srv media -"
  ];

  services.nginx.virtualHosts."manga.tigor.web.id" = {
    forceSSL = true;
    # TODO(auth wave): re-add auth gate (old config used tinyauth).
    locations."/".proxyPass = "http://127.0.0.1:4567";
  };
}
