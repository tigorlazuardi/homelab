# YTPTube — yt-dlp web GUI.
{
  homelab.containers.ytptube = {
    image = "ghcr.io/arabcoders/ytptube:latest";
    port = 8081;
    hostPort = 8082; # 8081 taken by container port; publish on host 8082
    uid = 1000;
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
    tmpfiles = [
      "d /srv/data/state/ytptube 0750 srv srv -"
      "d /srv/data/media/youtube 2775 srv media -"
    ];
  };
  # TODO(auth wave): re-add auth gate.
}
