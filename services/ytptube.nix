# YTPTube — yt-dlp web GUI. Single container, runs as uid 1000 inside.
{
  home-manager.users.srv.virtualisation.quadlet.containers.ytptube = {
    autoStart = true;
    containerConfig = {
      image = "ghcr.io/arabcoders/ytptube:latest";
      publishPorts = [ "127.0.0.1:8082:8081" ];
      userns = "keep-id:uid=1000,gid=1000";
      volumes = [
        "/srv/data/state/ytptube:/config"
        "/srv/data/media/youtube:/downloads"
      ];
      environments = {
        TZ = "Asia/Jakarta";
        YTP_MAX_WORKERS = "4";
        YTP_OUTPUT_TEMPLATE = "%(title).50s.%(ext)s";
        YTP_TEMP_DISABLED = "true";
      };
      noNewPrivileges = true;
      dropCapabilities = [ "all" ];
      autoUpdate = "registry";
    };
  };

  systemd.tmpfiles.rules = [
    "d /srv/data/state/ytptube 0750 srv srv -"
    "d /srv/data/media/youtube 2775 srv media -"
  ];

  services.nginx.virtualHosts."ytptube.tigor.web.id" = {
    forceSSL = true;
    # TODO(auth wave): re-add auth gate.
    locations."/".proxyPass = "http://127.0.0.1:8082";
  };
}
