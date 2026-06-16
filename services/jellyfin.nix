# Jellyfin — media server (read-only consumer of the wolf library). linuxserver
# s6 image (harden=false + PUID/PGID). Own login page, so NOT behind tinyauth
# (like immich/grafana). HW transcode via /dev/dri/renderD128. Config carried from
# the old deploy at /var/mnt/state/jellyfin (same path → chown at cutover).
{
  homelab.containers.jellyfin = {
    image = "lscr.io/linuxserver/jellyfin:latest";
    port = 8096;
    subdomain = "jellyfin";
    uid = 1000;
    harden = false; # linuxserver s6 init needs caps
    volumes = [
      "/var/mnt/state/jellyfin/config:/config"
      "/var/mnt/state/jellyfin/cache:/cache"
      # library is read-only to Jellyfin — arr owns writes. Matches new layout.
      "/var/mnt/wolf/media:/media:ro"
    ];
    environments = {
      TZ = "Asia/Jakarta";
      PUID = "1000";
      PGID = "1000";
      UMASK = "002";
      JELLYFIN_PublishedServerUrl = "https://jellyfin.tigor.web.id";
    };
    # VAAPI transcode — renderD128 is world-rw (0666), no extra group needed.
    extraContainerConfig.devices = [ "/dev/dri/renderD128" ];
    # Jellyfin needs WebSocket upgrade for live sync / remote control.
    nginx.extraConfig = ''
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
    '';
    tmpfiles = [
      "d /var/mnt/state/jellyfin 0750 srv media -"
      "d /var/mnt/state/jellyfin/config 0750 srv media -"
      "d /var/mnt/state/jellyfin/cache 0750 srv media -"
    ];
  };
}
