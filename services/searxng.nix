# SearXNG — privacy metasearch. Two containers (core + valkey) on a private
# rootless network so they resolve each other by name.
{ config, ... }:
{
  # core writes as uid 977 inside; valkey as 999 → keep-id maps each to host srv.
  home-manager.users.srv =
    { config, ... }:
    let
      inherit (config.virtualisation.quadlet) networks;
    in
    {
      virtualisation.quadlet = {
        networks.searxng = { };

        # Re-enabled. The original disable was a CPU-greed concern; the CPU budget
        # tiering (modules/cpu-budget.nix + .claude/rules/cpu-priority.md) now caps
        # it — placed in media-batch.slice so a query storm yields to jellyfin and
        # coding sessions instead of starving the host. Bump to media-interactive
        # if interactive search latency under load becomes annoying.
        containers.searxng = {
          autoStart = true;
          serviceConfig = {
            Restart = "always";
            RestartSec = "10";
            Slice = "media-batch.slice";
          };
          containerConfig = {
            image = "docker.io/searxng/searxng:latest";
            publishPorts = [ "127.0.0.1:8080:8080" ];
            networks = [ networks.searxng.ref ];
            userns = "keep-id:uid=977,gid=977";
            volumes = [
              "/var/mnt/state/searxng/config:/etc/searxng:Z"
              "/var/mnt/state/searxng/data:/var/cache/searxng"
            ];
            environments = {
              TZ = "Asia/Jakarta";
              SEARXNG_REDIS__URL = "redis://searxng-valkey:6379/0";
              # SEARXNG_SECRET: provide via mounted settings.yml or a sops secret
              # at cutover (searxng needs a stable secret_key).
            };
            noNewPrivileges = true;
            dropCapabilities = [ "all" ];
            autoUpdate = "registry";
          };
        };

        containers.searxng-valkey = {
          autoStart = true; # paired with searxng
          serviceConfig = {
            Restart = "always";
            RestartSec = "10";
            Slice = "media-batch.slice";
          };
          containerConfig = {
            image = "docker.io/valkey/valkey:9-alpine";
            networks = [ networks.searxng.ref ];
            userns = "keep-id:uid=999,gid=999";
            exec = "valkey-server --save 30 1 --loglevel warning";
            volumes = [ "/var/mnt/state/searxng/valkey:/data" ];
            environments.TZ = "Asia/Jakarta";
            noNewPrivileges = true;
            dropCapabilities = [ "all" ];
            autoUpdate = "registry";
          };
        };
      };
    };

  systemd.tmpfiles.rules = [
    "d /var/mnt/state/searxng 0750 srv srv -"
    "d /var/mnt/state/searxng/config 0750 srv srv -"
    "d /var/mnt/state/searxng/data 0750 srv srv -"
    "d /var/mnt/state/searxng/valkey 0750 srv srv -"
  ];

  # Private vhost: LAN + wireguard VPN only, no internet exposure. No tinyauth so
  # the JSON API (?format=json) stays callable from allowed IPs. Ranges come from
  # homelab.nginx.trustedRanges (modules/quadlet-service.nix) — edit there to
  # update all private vhosts at once. Container peers do NOT use this path — they
  # join the `searxng` podman network and hit http://searxng:8080 directly (see
  # .claude/rules/container-networking.md).
  services.nginx.virtualHosts."searxng.tigor.web.id" = {
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8080";
      extraConfig = config.homelab.nginx.privateAllow;
    };
  };
}
