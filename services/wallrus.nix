# wallrus — homelab wallpaper collector (own image). Uses PUID/PGID (chowns its
# data dir → harden=false). Push-deploy via a root webhook hook that restarts the
# srv user unit.
{ config, pkgs, ... }:
{
  sops.secrets."wallrus.env" = {
    sopsFile = ../secrets/wallrus.env;
    format = "dotenv";
    key = "";
    owner = "srv";
  };

  homelab.containers.wallrus = {
    image = "ghcr.io/tigorlazuardi/wallrus:latest";
    port = 5173;
    uid = 1000;
    harden = false; # PUID/PGID → chowns data dir, needs caps
    volumes = [ "/srv/data/state/wallrus:/data/wallrus" ];
    environments = {
      PUID = "1000";
      PGID = "1000";
      WALLRUS_LISTEN_ADDR = "0.0.0.0:5173";
      WALLRUS_TRUST_PROXY = "true";
      WALLRUS_DATA_DIR = "/data/wallrus";
      # OTLP → Alloy gateway (lands once observability wave is up).
      OTEL_EXPORTER_OTLP_ENDPOINT = "https://otlp.tigor.web.id";
      OTEL_RESOURCE_ATTRIBUTES = "deployment.environment.name=production,deployment.environment=production,service.namespace=wallrus";
      OTEL_SERVICE_NAME = "wallrus";
    };
    environmentFiles = [ config.sops.secrets."wallrus.env".path ];
    tmpfiles = [ "d /srv/data/state/wallrus 2775 srv media -" ];
  };

  # Push-to-deploy: webhook (root) restarts the rootless srv user unit.
  # TODO(cutover): verify the --machine user-bus restart works under linger.
  services.webhook.hooks."deploy-wallrus" = {
    execute-command = "${pkgs.writeShellScript "deploy-wallrus" ''
      ${pkgs.podman}/bin/podman --remote=false pull ghcr.io/tigorlazuardi/wallrus:latest || true
      ${pkgs.systemd}/bin/systemctl --user --machine=srv@.host restart wallrus.service
    ''}";
    response-message = "Wallrus deployment triggered";
  };
}
