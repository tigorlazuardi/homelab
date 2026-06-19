# Immich — self-hosted photos/videos. Four containers (server + machine-learning
# + valkey + postgres) on a private rootless network so they resolve each other
# by name. Fresh database this round (state SSD); the 236G of OLD originals from
# the previous rootful deploy are mounted READ-ONLY and re-indexed as an Immich
# "External Library" (immich never writes them — generated thumbs/previews land
# in the NEW managed upload). Storage tiers (see .claude/rules/storage.md):
#   photos / managed upload  → fenrir  (sentimental, irreplaceable)
#   old originals (:ro)       → fenrir  (the previous deploy's upload tree)
#   db / valkey / ML cache    → state   (rebuildable, fast R/W → SSD)
{ config, ... }:
let
  domain = "photos.tigor.web.id";
  # Captured from the SYSTEM scope (the inner home-manager block shadows `config`).
  envPath = config.sops.secrets."immich.env".path;
in
{
  sops.secrets."immich.env" = {
    sopsFile = ../secrets/immich.env;
    format = "dotenv";
    key = "";
    owner = "srv"; # rootless containers (srv user) must read it
  };

  home-manager.users.srv =
    { config, ... }:
    let
      inherit (config.virtualisation.quadlet) networks;
    in
    {
      virtualisation.quadlet = {
        networks.immich = { };

        containers.immich-server = {
          autoStart = true;
          unitConfig = {
            After = [
              "immich-postgres.service"
              "immich-valkey.service"
            ];
            Wants = [
              "immich-postgres.service"
              "immich-valkey.service"
            ];
          };
          # Bulk imports spawn parallel ffmpeg (thumbnail + video transcode) that
          # peg all 8 threads → load ~18, 100°C thermal throttle, host goes
          # unresponsive. Cap CPU + deprioritize so system/interactive work always
          # wins; the import just runs slower. (Also lower per-job concurrency in
          # Immich Admin → Job Settings: Thumbnail Generation + Video Transcoding.)
          serviceConfig = {
            CPUQuota = "400%"; # ≤4 of 8 threads
            CPUWeight = "30"; # loses to default-weight (100) system tasks
          };
          containerConfig = {
            image = "ghcr.io/immich-app/immich-server:release";
            publishPorts = [ "127.0.0.1:2283:2283" ];
            networks = [ networks.immich.ref ];
            # Immich backend calls dex server-side (OIDC discovery, token,
            # userinfo). Rootless pasta can't hairpin to the host's own LAN IP,
            # so reaching dex via its public URL fails → route it to the host
            # gateway; nginx serves the dex vhost by SNI/Host header.
            addHosts = [ "dex.tigor.web.id:host-gateway" ];
            userns = null; # immich-server runs as root-in-userns → host srv
            # HW transcoding (world-rw render node → no extra group needed).
            devices = [ "/dev/dri/renderD128" ];
            volumes = [
              # NEW managed upload (thumbs, previews, freshly-imported originals) → fenrir
              "/var/mnt/fenrir/immich/upload:/usr/src/app/upload"
              # OLD originals from the previous deploy — read-only External Library
              "/var/mnt/fenrir/immich/server/library:/mnt/external/old:ro"
            ];
            environments = {
              TZ = "Asia/Jakarta";
              NO_COLOR = "true";
              REDIS_HOSTNAME = "immich-valkey";
              DB_HOSTNAME = "immich-postgres";
              DB_USERNAME = "immich";
              DB_DATABASE_NAME = "immich";
            };
            environmentFiles = [ envPath ]; # DB_PASSWORD
            autoUpdate = "registry";
          };
        };

        containers.immich-machine-learning = {
          autoStart = true;
          # ML (face/CLIP) inference also CPU-bound (no GPU). Cap harder than the
          # server so the two together can't saturate the box.
          serviceConfig = {
            CPUQuota = "200%"; # ≤2 of 8 threads
            CPUWeight = "20";
          };
          containerConfig = {
            image = "ghcr.io/immich-app/immich-machine-learning:release";
            networks = [ networks.immich.ref ];
            userns = null; # runs as root-in-userns → host srv
            volumes = [
              # model cache is rebuildable (re-downloaded on demand) → SSD
              "/var/mnt/state/immich/model-cache:/cache"
            ];
            environments.TZ = "Asia/Jakarta";
            autoUpdate = "registry";
          };
        };

        containers.immich-valkey = {
          autoStart = true;
          containerConfig = {
            image = "docker.io/valkey/valkey:8-bookworm";
            networks = [ networks.immich.ref ];
            userns = "keep-id:uid=999,gid=999"; # valkey drops to 999 → host srv
            exec = "valkey-server --save 30 1 --loglevel warning";
            volumes = [ "/var/mnt/state/immich/valkey:/data" ];
            environments.TZ = "Asia/Jakarta";
            noNewPrivileges = true;
            dropCapabilities = [ "all" ];
            autoUpdate = "registry";
          };
        };

        containers.immich-postgres = {
          autoStart = true;
          containerConfig = {
            # vectorchord/pgvecto.rs build Immich requires — keep in lockstep with
            # the server image per Immich's published compose.
            image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0";
            networks = [ networks.immich.ref ];
            userns = "keep-id:uid=999,gid=999"; # postgres drops to 999 → host srv
            volumes = [
              # FRESH database this round → SSD
              "/var/mnt/state/immich/postgres:/var/lib/postgresql/data"
            ];
            environments = {
              POSTGRES_USER = "immich";
              POSTGRES_DB = "immich";
              POSTGRES_INITDB_ARGS = "--data-checksums";
            };
            environmentFiles = [ envPath ]; # POSTGRES_PASSWORD
            # postgres needs SHM for parallel query / vector ops.
            shmSize = "128m";
            autoUpdate = "registry";
          };
        };
      };
    };

  systemd.tmpfiles.rules = [
    # state (SSD) — db / cache, owned srv (private; not in media group).
    "d /var/mnt/state/immich 0750 srv srv -"
    "d /var/mnt/state/immich/postgres 0700 srv srv -"
    "d /var/mnt/state/immich/valkey 0750 srv srv -"
    "d /var/mnt/state/immich/model-cache 0750 srv srv -"
    # fenrir (HDD) — photos. NEW managed upload only; the OLD `server/` tree from
    # the previous deploy already exists and is mounted :ro (not created here).
    "d /var/mnt/fenrir/immich 2775 srv media -"
    "d /var/mnt/fenrir/immich/upload 2775 srv media -"
  ];

  services.nginx.virtualHosts."${domain}" = {
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:2283";
      extraConfig = ''
        client_max_body_size 100G;
        proxy_read_timeout 1h;
        proxy_send_timeout 1h;
      '';
    };
  };
}
