# herdr-web-tui — browser frontend for the running herdr server (the same single
# daemon herdr-sessions.nix owns). Streams the live herdr TUI over HTTP+WebSocket.
# Runs as a systemd --user service (homeserver), bound to 127.0.0.1:8505, behind
# the private nginx vhost in services/herdr-web-tui.nix.
#
# Uses the upstream flake's home-manager module. The herdr binary it shells out
# to is resolved from home-manager's programs.herdr (pkgs.herdr), which
# herdr-sessions.nix enables — the same binary that module runs the daemon from,
# so CLI and daemon match. server.enable stays OFF: herdr-server is already owned
# by herdr-sessions.nix; this just attaches to it.
{ inputs, ... }:
{
  imports = [ inputs.herdr-web-tui.homeManagerModules.default ];

  services.herdr-web-tui = {
    enable = true;
    # herdrPackage left unset → the module falls back to config.programs.herdr.package
    # (pkgs.herdr), enabled via programs.herdr.enable in herdr-sessions.nix.
    server.enable = false; # herdr-server owned by herdr-sessions.nix
    addr = "127.0.0.1:8505"; # loopback only; nginx is the sole ingress
    logFormat = "json"; # journald -> Alloy -> Loki (structured)
    # herdr TUI client needs a color-capable terminal; user units inherit none.
    environment = {
      TERM = "xterm-256color";
      COLORTERM = "truecolor";
    };
  };

  # Coding-tier CPU priority — same slice as the herdr daemon it fronts
  # (cpu-priority.md). The upstream module sets no Slice; add it here (deep-merges
  # into the module's Service block).
  systemd.user.services.herdr-web-tui.Service.Slice = "sessions.slice";
}
