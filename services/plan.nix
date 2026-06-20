{ config, ... }:
{
  sops.secrets."plan-env" = {
    sopsFile = ../secrets/plan.env;
    format = "dotenv";
    key = "";
    owner = "srv";
  };
  homelab.containers.plan = {
    image = "localhost/plan:latest";
    autoUpdate = "local"; # never pull a registry for a local image
    port = 3000; # container port
    hostPort = 3050; # loopback publish (3000 = adguard)
    uid = 1000; # node user → keep-id → host srv
    auth = true; # tinyauth whole vhost
    volumes = [
      "/var/mnt/state/plan/data:/data"
      "/var/mnt/state/plan/plans:/plans"
    ];
    environments = {
      TZ = "Asia/Jakarta";
      NODE_ENV = "development"; # REQUIRED for local no-login actions (not production)
      PLAN_LOCAL_MODE = "1";
      PORT = "3000";
      DATABASE_URL = "file:/data/app.db";
      BETTER_AUTH_URL = "https://plan.tigor.web.id";
      PLAN_LOCAL_DIR = "/plans";
    };
    environmentFiles = [ config.sops.secrets."plan-env".path ];
    extraContainerConfig = { pull = "never"; };
    serviceConfig = { Slice = "media-batch.slice"; };
    tmpfiles = [
      "d /var/mnt/state/plan 2750 srv media -" # media can traverse into plans/ below
      "d /var/mnt/state/plan/data 0750 srv srv -"
      "d /var/mnt/state/plan/plans 2770 srv media -" # setgid+media → homeserver writes MDX, srv container R/W
    ];
  };
}
