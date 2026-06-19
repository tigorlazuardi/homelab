{
  imports = [
    ./nginx.nix
    # host / native (privileged ports / kernel)
    ./adguardhome.nix
    ./wireguard.nix
    ./samba.nix
    ./smartd.nix
    # auth (forward-auth proxy + IdP; declares the per-vhost tinyauth option)
    ./auth.nix
    # observability (native Alloy gateway + Prometheus/Loki/Tempo/Grafana)
    ./observability.nix
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
    ./flaresolverr.nix
    ./searxng.nix
    ./suwayomi.nix
    ./ytptube.nix
    ./jdownloader.nix
    ./navidrome.nix
    ./qbittorrent.nix
    ./immich.nix
    ./paperless-ngx.nix
    ./infisical.nix
    ./webhook.nix
    ./wallrus.nix
  ];
}
