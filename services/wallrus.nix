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
    harden = false; # entrypoint may chown the data dir on the classic-docker path
    # keep-id:uid=1000 (helper default) → the container runs as host srv (1001),
    # which owns /var/mnt/state/wallrus. The image entrypoint (>= 66c7c7e) detects
    # it is already non-root and skips the setpriv privilege-drop, so no userns
    # workaround is needed. (An earlier image setpriv-dropped unconditionally and
    # crash-looped here with `setpriv: setgroups failed` — fixed image-side.)
    volumes = [ "/var/mnt/state/wallrus:/data/wallrus" ];
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
    tmpfiles = [ "d /var/mnt/state/wallrus 2775 srv media -" ];
  };

  # Push-to-deploy: webhook (root) pulls + restarts the rootless srv user unit.
  # Both steps run AS srv (runuser → srv's user bus via XDG_RUNTIME_DIR). The pull
  # MUST happen in srv's rootless image store — a root-side `podman pull` lands in
  # root's store and the srv unit never sees the new image (the bug that left the
  # container stale across deploys). On restart the quadlet unit re-resolves
  # :latest from srv's now-updated store. linger keeps /run/user/1001 alive at boot.
  services.webhook.hooks."deploy-wallrus" = {
    execute-command = "${pkgs.writeShellScript "deploy-wallrus" ''
      runuser='${pkgs.util-linux}/bin/runuser -u srv -- env XDG_RUNTIME_DIR=/run/user/1001'
      $runuser ${pkgs.podman}/bin/podman pull ghcr.io/tigorlazuardi/wallrus:latest || true
      $runuser ${pkgs.systemd}/bin/systemctl --user restart wallrus.service
    ''}";
    response-message = "Wallrus deployment triggered";
  };
}
