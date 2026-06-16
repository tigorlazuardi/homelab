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
    # *arr media-automation stack
    ./prowlarr.nix
    ./sonarr.nix
    ./radarr.nix
    ./bazarr.nix
    ./flaresolverr.nix
    ./searxng.nix
    ./suwayomi.nix
    ./ytptube.nix
    ./jdownloader.nix
    ./navidrome.nix
    ./qbittorrent.nix
    ./paperless-ngx.nix
    ./infisical.nix
    ./webhook.nix
    ./wallrus.nix
  ];
}
