# YTPTube — yt-dlp web GUI.
{
  homelab.containers.ytptube = {
    image = "ghcr.io/arabcoders/ytptube:latest";
    port = 8081;
    hostPort = 8082; # 8081 taken by container port; publish on host 8082
    uid = 1000;
    # Batch media slice: yt-dlp downloads yield to both jellyfin (interactive) and
    # homeserver coding sessions (see modules/cpu-budget.nix). CPUWeight within
    # media-batch.slice governs share vs other batch services (immich).
    serviceConfig = {
      Slice = "media-batch.slice";
      CPUWeight = "20";
    };
    volumes = [
      "/var/mnt/state/ytptube:/config"
      "/var/mnt/wolf/media/youtube:/downloads"
    ];
    environments = {
      TZ = "Asia/Jakarta";
      YTP_MAX_WORKERS = "4";
      YTP_OUTPUT_TEMPLATE = "%(title).50s.%(ext)s";
      YTP_TEMP_DISABLED = "true";
    };
    tmpfiles = [
      "d /var/mnt/state/ytptube 0750 srv srv -"
      "d /var/mnt/wolf/media/youtube 2775 srv media -"
    ];
    # Gate whole vhost behind tinyauth SSO (see services/auth.nix). ytptube
    # exposes a download-trigger API on the same vhost; no external bookmarklet
    # poster relies on it, so the full vhost is gated. Browser carries the SSO
    # cookie, so the GUI websocket works once authed.
    auth = true;
  };
}
