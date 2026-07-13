# herdr-web-tui — browser frontend for the running herdr server (the same single
# daemon herdr-sessions.nix owns). Streams the live herdr TUI over HTTP+WebSocket.
# Runs as a systemd --user service (homeserver), bound to 127.0.0.1:8505, behind
# the private nginx vhost in services/herdr-web-tui.nix.
#
# Uses the upstream flake's home-manager module but DISCARDS its herdr-package
# resolution (pkgs.herdr / programs.herdr) — herdrPackage is pinned to our flake
# input, the same herdr binary herdr-sessions.nix runs the daemon from, so the
# CLI this shells out to matches the daemon. server.enable stays OFF: herdr-server
# is already owned by herdr-sessions.nix; this just attaches to it.
{ pkgs, inputs, ... }:
let
  herdr = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  imports = [ inputs.herdr-web-tui.homeManagerModules.default ];

  services.herdr-web-tui = {
    enable = true;
    herdrPackage = herdr; # discard the module's pkgs.herdr fallback
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
