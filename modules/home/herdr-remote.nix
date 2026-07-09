# herdr-remote — self-hosted relay (dcolinmorgan/herdr-remote) to monitor/approve
# local herdr agents from a phone. Two systemd --user (homeserver) daemons:
#   * herdr-remote: relay/herdr_relay.py — polls the local herdr binary, serves a
#     WebSocket + HTTP POST on 8375, broadcasts agent state to WS clients.
#   * herdr-remote-telegram: relay/herdr_telegram.py — bridges the relay WS to a
#     Telegram bot (push + approve from the phone) using a sops-provided token.
# web/index.html is a single static file (no build) — nginx serves it directly and
# the client pastes the relay wss:// URL + optional token into a settings field
# (localStorage), so no server-side templating is needed.
#
# Mixed scope in one file (locality of behaviour, .claude/rules/conventions.md):
# system nginx vhost + sops secret live here alongside the home-manager (homeserver)
# systemd --user services, imported at system level via services/default.nix (NOT
# into modules/users.nix's home-manager.users.homeserver.imports list — that list is
# pure home-manager submodules with no access to set system-level services.nginx /
# sops.secrets; see services/plan.nix, services/immich.nix, services/wallrus.nix for
# the same mixed-scope-in-one-file pattern used here).
#
# Telemetry: deliberately none. These are personal single-user systemd units for a
# single operator's phone-relay — journald structured logs (automatic via systemd)
# are the observability surface; OpenTelemetry tracing/metrics would be overkill.
{
  inputs,
  pkgs,
  config,
  ...
}:
let
  src = pkgs.fetchFromGitHub {
    owner = "dcolinmorgan";
    repo = "herdr-remote";
    rev = "468aff7b3da9c17337bf25c5c181ec9fb32033ce";
    hash = "sha256-/iZgXMXYsiVPiKme3eDOiFCzAaw3C9JKz4xJhqMMgdY=";
  };

  herdr = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;

  pyRelay = pkgs.python3.withPackages (ps: [
    ps.websockets
    ps.zeroconf
  ]);
  pyTg = pkgs.python3.withPackages (ps: [
    ps.websockets
    ps.python-telegram-bot
  ]);

  telegramEnvFile = config.sops.secrets."herdr-remote-telegram".path;
in
{
  sops.secrets."herdr-remote-telegram" = {
    sopsFile = ../../secrets/herdr-remote-telegram.env;
    format = "dotenv";
    key = "";
    owner = "homeserver";
  };

  services.nginx.virtualHosts."herdr.tigor.web.id" = {
    forceSSL = true;
    locations."/" = {
      root = "${src}/web";
      index = "index.html";
      extraConfig = config.homelab.nginx.privateAllow;
    };
    locations."/ws" = {
      proxyPass = "http://127.0.0.1:8375/";
      proxyWebsockets = true;
      extraConfig = config.homelab.nginx.privateAllow;
    };
  };

  home-manager.users.homeserver = {
    systemd.user.services.herdr-remote = {
      Unit = {
        Description = "herdr-remote relay (WS + HTTP bridge to local herdr agents)";
        After = [ "herdr-server.service" ];
      };
      Install.WantedBy = [ "default.target" ];
      Service = {
        ExecStart = "${pyRelay}/bin/python ${src}/relay/herdr_relay.py";
        Environment = [
          "HERDR_BIN=${herdr}/bin/herdr"
          "HERDR_RELAY_PORT=8375"
        ];
        Slice = "sessions.slice";
        Restart = "always";
        RestartSec = 5;
      };
    };

    systemd.user.services.herdr-remote-telegram = {
      Unit = {
        Description = "herdr-remote Telegram bridge (push + approve from phone)";
        After = [ "herdr-remote.service" ];
      };
      Install.WantedBy = [ "default.target" ];
      Service = {
        ExecStart = "${pyTg}/bin/python ${src}/relay/herdr_telegram.py";
        Environment = [ "HERDR_RELAY=ws://127.0.0.1:8375" ];
        EnvironmentFile = telegramEnvFile;
        Slice = "sessions.slice";
        Restart = "always";
        RestartSec = 10;
      };
    };
  };
}
