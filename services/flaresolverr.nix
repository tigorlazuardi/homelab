# FlareSolverr — pilot service for the rootless-quadlet pattern.
# Stateless: no volume, no secret, no inter-container dep → safe first migration.
#
# Pattern every rootless service follows:
#   - runs under `srv` (userns=keep-id → files land owned by srv:media on disk)
#   - publishes ONLY to host loopback; nginx (host) is the sole ingress
#   - hardened: cap-drop all + no-new-privileges
{
  # Rootless container under the srv user (Home Manager quadlet).
  home-manager.users.srv.virtualisation.quadlet.containers.flaresolverr = {
    autoStart = true;
    containerConfig = {
      image = "ghcr.io/flaresolverr/flaresolverr:latest";
      publishPorts = [ "127.0.0.1:8191:8191" ]; # host loopback only
      userns = "keep-id";
      environments = {
        TZ = "Asia/Jakarta";
        LOG_LEVEL = "info";
      };
      # Hardening.
      noNewPrivileges = true;
      dropCapabilities = [ "all" ];
      # Auto-update: adds io.containers.autoupdate=registry; picked up by the
      # per-user podman-auto-update.timer (srv has linger).
      autoUpdate = "registry";
    };
  };

  # Host nginx → loopback published port.
  services.nginx.virtualHosts."flaresolverr.tigor.web.id" = {
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:8191";
  };
}
