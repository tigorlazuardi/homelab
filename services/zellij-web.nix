# zellij web — native zellij web server so the homeserver user's durable claude
# sessions (modules/home/claude-sessions.nix) can be reached from a browser AND
# attached natively from a local machine:
#
#   zellij attach https://zellij.tigor.web.id/<session> --token <t> --remember
#
# AUTH = zellij's own login token, by design. NOT tinyauth:
#   tinyauth is browser SSO forward-auth; the `zellij attach` CLI carries only the
#   zellij token (no SSO cookie), so a tinyauth gate would 401 the CLI. The two are
#   mutually exclusive on one endpoint. zellij's token is the purpose-built auth
#   here (hashed in a local db, revocable, with a read-only variant) — it is the gate.
#
# SECURITY (remote shell over HTTP — high-value):
#   * The token is the ONLY gate. It is a strong bearer secret: store it in a
#     password manager, never commit it, revoke if leaked (`--revoke-token`).
#   * Bind LOOPBACK only (127.0.0.1:7682); the port is never opened in the
#     firewall. nginx is the sole ingress and terminates public TLS.
#   * zellij web has NO built-in rate-limiting (DoS) — docs require a reverse proxy
#     for this. nginx applies a per-client limit_req zone below.
#   * Blast radius: a token holder gets a full shell as `homeserver` and, via the
#     zellij session-manager, every running session. Treat the token like SSH keys.
#
# PREREQUISITE — web_sharing: zellij defaults `web_sharing "off"`, so sessions
# REJECT web attach ("not allowed to attach to this session"). The homeserver
# config.kdl (intentionally unmanaged, see modules/home/claude-sessions.nix) sets
# `web_sharing "on"` so sessions opt in. A session only shares "if the web server
# is online" at its start — hence the session units order After=zellij-web.service
# (modules/home/claude-sessions.nix). Sessions created before this was set must be
# restarted once: `systemctl --user restart 'zellij-*'`.
#
# One-time token setup after `nixos-rebuild switch` (as the homeserver user); the
# secret is shown ONCE — copy it straight into the password manager:
#   zellij web --create-token                       # full read/write
#   zellij web --create-token --create-read-only-token   # view-only (watcher)
#   zellij web --list-tokens / --revoke-token <name>
{ ... }:
let
  port = 7682; # loopback only; 8082 (zellij web default) is taken by ytptube
  userPath = "/home/homeserver/.bun/bin:/etc/profiles/per-user/homeserver/bin:/run/current-system/sw/bin:/usr/bin:/bin";
in
{
  # Per-client rate-limit zone (http context). $binary_remote_addr is the real
  # client IP because nginx trusts Cloudflare's CF-Connecting-IP (services/nginx.nix).
  services.nginx.appendHttpConfig = ''
    limit_req_zone $binary_remote_addr zone=zellij_web:10m rate=10r/s;
  '';

  # Public ingress: TLS + rate-limit → loopback zellij web. NO tinyauth (would
  # break native CLI attach). proxyWebsockets defaults true (services/nginx.nix);
  # raise timeouts so an idle terminal websocket is not dropped.
  services.nginx.virtualHosts."zellij.tigor.web.id" = {
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      extraConfig = ''
        limit_req zone=zellij_web burst=20 nodelay;
        proxy_read_timeout 1d;
        proxy_send_timeout 1d;
      '';
    };
  };

  # The web server, as a homeserver user service so it serves that user's sessions.
  # Foreground (no --daemonize) so systemd supervises + restarts it.
  home-manager.users.homeserver =
    { pkgs, ... }:
    {
      systemd.user.services.zellij-web = {
        Unit.Description = "zellij web server (browser + native remote attach)";
        Install.WantedBy = [ "default.target" ];
        Service = {
          Type = "simple";
          Environment = [
            "PATH=${userPath}"
            "HOME=/home/homeserver"
          ];
          ExecStart = "${pkgs.zellij}/bin/zellij web --ip 127.0.0.1 --port ${toString port}";
          Slice = "sessions.slice"; # coding tier (see modules/cpu-budget.nix)
          Restart = "always";
          RestartSec = 5;
        };
      };
    };
}
