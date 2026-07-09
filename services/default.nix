{
  imports = [
    ./nginx.nix
    # host / native (privileged ports / kernel)
    ./adguardhome.nix
    ./wireguard.nix
    ./tailscale.nix
    ./samba.nix
    ./smartd.nix
    # auth (forward-auth proxy + IdP; declares the per-vhost tinyauth option)
    ./auth.nix
    # observability (native Alloy gateway + Prometheus/Loki/Tempo/Grafana)
    ./observability.nix
    # below: cgroup v2 time-travel resource monitor + ttyd browser TUI
    ./below.nix
    # rootless app services
    # shared CPU budget (one slice) for media-processing services: immich + jellyfin
    ./media-slice.nix
    # *arr media-automation stack
    ./prowlarr.nix
    ./sonarr.nix
    ./sonarr-anime.nix
    ./radarr.nix
    ./bazarr.nix
    ./recyclarr.nix
    ./jellyfin.nix
    ./seerr.nix
    ./plan.nix
    ./flaresolverr.nix
    ./searxng.nix
    ./suwayomi.nix
    ./ytptube.nix
    ./jdownloader.nix
    ./navidrome.nix
    ./omniroute.nix
    ../modules/home/herdr-remote.nix
    ./qbittorrent.nix
    ./immich.nix
    ./paperless-ngx.nix
    ./infisical.nix
    ./webhook.nix
    ./wallrus.nix
  ];
}
