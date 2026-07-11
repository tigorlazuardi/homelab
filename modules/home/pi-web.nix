# pi-web — mobile web UI for the Pi Coding Agent (@jmfederico/pi-web). Runs as a
# systemd --user service (homeserver), bound to 127.0.0.1:8504. Deliberately
# non-deterministic: ExecStartPre uses bun to install/update pi-web + the pi
# coding-agent to latest on every (re)start (user does not want a pinned,
# buildNpmPackage-style deterministic package here). No auth, no sops — the user
# handles Pi login himself later (see services/pi-web.nix for the private vhost).
{
  pkgs,
  config,
  ...
}:
let
  home = config.home.homeDirectory;

  # Pin point: bump to a concrete version (e.g. "0.3.1") to stop tracking latest.
  piWebVersion = "latest";

  # Same PATH shape as herdr-sessions.nix's userPath: bun global bin (pi-web +
  # pi land here), the user profile, then the system profile — gives bun, node
  # (nodejs is system-wide), git, gcc, python3 (node-pty source-compile fallback).
  userPath = "${home}/.bun/bin:/etc/profiles/per-user/homeserver/bin:/run/current-system/sw/bin:/usr/bin:/bin";

  # `bun install -g` does NOT run install/postinstall lifecycle scripts for
  # untrusted deps — node-pty's native addon (pty.node) is built by exactly
  # that script (node-gyp), so a plain `bun install -g` leaves pty.node
  # missing and pi-web-sessiond throws on `require("node-pty")` at startup
  # (crash-loop, socket never created, pi-web-server 502s forever).
  #
  # Fix: after the bun install, check whether node-pty actually loads; if not,
  # build it ourselves with node-gyp against the SAME nodejs derivation that
  # ends up on this unit's PATH (pkgs.nodejs, via home.packages in
  # modules/home/agents.nix) — npm_config_nodedir points node-gyp at that
  # store path's bundled headers so it never needs network access to fetch
  # matching headers, and the built addon's ABI matches the node that will
  # `require()` it at runtime. Verified manually: `node-gyp rebuild` with
  # npm_config_nodedir=${pkgs.nodejs} + node-gyp from ${pkgs.node-gyp}
  # succeeds offline and produces a loadable build/Release/pty.node.
  piWebInstall = pkgs.writeShellScript "pi-web-install" ''
    set -euo pipefail

    bun install -g @jmfederico/pi-web@${piWebVersion} @mariozechner/pi-coding-agent@${piWebVersion}

    ptyDir="${home}/.bun/install/global/node_modules/node-pty"
    if [ -d "$ptyDir" ] && ! node -e 'require(process.argv[1])' "$ptyDir" >/dev/null 2>&1; then
      echo "pi-web: node-pty native module missing/broken — building via node-gyp" >&2
      ( cd "$ptyDir" && npm_config_nodedir=${pkgs.nodejs} ${pkgs.node-gyp}/bin/node-gyp rebuild )
      # Fail loud: if it still doesn't load after a rebuild, don't silently
      # start sessiond into the same crash loop this is fixing.
      node -e 'require(process.argv[1])' "$ptyDir"
    fi
  '';
in
{
  # pi-web is TWO long-lived processes (docs: pi-web.dev/install "Manual
  # processes") — pi-web-sessiond (spawns/owns pi coding-agent sessions) and
  # pi-web-server (the web/API, proxies session I/O to sessiond). The server
  # 502s on /api/machines/local/* if sessiond isn't running. They talk over a
  # unix socket that both derive from the same default ($HOME/.pi-web/sessiond.sock,
  # dist/sessiond/config.js) — do NOT override it with a custom path, that risks
  # only one side rebinding; same $HOME (both run as homeserver) already keeps
  # them in agreement. The server is loosely coupled to the daemon (Wants+After,
  # not PartOf/Requires) since it just reconnects to the socket per-request —
  # see the `pi-web` unit below for why.
  systemd.user.services = {
    # The daemon. Owns the install gate: ExecStartPre installs/updates both
    # packages to latest before EITHER process can start.
    pi-web-sessiond = {
      Unit.Description = "pi-web session daemon (spawns pi coding-agent sessions)";
      Install.WantedBy = [ "default.target" ];
      Service = {
        Type = "simple";
        Slice = "sessions.slice";
        Restart = "always";
        RestartSec = 5;
        WorkingDirectory = home;
        Environment = [
          "PATH=${userPath}"
        ];
        # Installs/updates both packages to latest, and (re)builds node-pty's
        # native addon if needed, on every (re)start. Not wrapped in `-`
        # (allowed to fail): a broken/missing install should surface loudly
        # on first start rather than silently leaving the old ExecStart with
        # nothing to run; Restart=always handles transient network blips on
        # subsequent restarts by retrying the whole unit.
        ExecStartPre = "${piWebInstall}";
        ExecStart = "%h/.bun/bin/pi-web-sessiond";
        # sessiond ignores SIGTERM (logs "shutting down session daemon" but
        # never exits) — every stop/restart/switch was hitting systemd's
        # 90s default TimeoutStopSec then SIGKILL ("State 'stop-sigterm'
        # timed out. Killing."), hanging every nixos-rebuild switch ~90s.
        # Session state is persisted to disk by the daemon, so a bounded
        # kill is safe. Try SIGINT first (node daemons often exit cleanly
        # on SIGINT where they ignore SIGTERM); cap the wait at 15s so a
        # still-hung process gets SIGKILLed quickly instead of at 90s.
        KillSignal = "SIGINT";
        TimeoutStopSec = 15;
      };
    };

    # The web/API server. Kept named `pi-web` so `journalctl --user -u pi-web`
    # still works. The server is a proxy that connects to the sessiond unix
    # socket per-request — it does NOT need to be torn down when sessiond
    # restarts, it just reconnects to the new socket. Wants+After gives boot
    # ordering (socket exists first) + pull-in without PartOf's stop
    # propagation — PartOf previously meant a sessiond restart also stopped
    # the server, and nothing brought it back (502 until manually started).
    pi-web = {
      Unit = {
        Description = "pi-web (mobile web UI for the Pi coding agent)";
        Wants = [ "pi-web-sessiond.service" ];
        After = [ "pi-web-sessiond.service" ];
      };
      Install.WantedBy = [ "default.target" ];
      Service = {
        Type = "simple";
        Slice = "sessions.slice";
        Restart = "always";
        RestartSec = 5;
        WorkingDirectory = home;
        Environment = [
          "PATH=${userPath}"
          "PI_WEB_HOST=127.0.0.1"
          "PI_WEB_PORT=8504"
          "PI_WEB_ALLOWED_HOSTS=pi.tigor.web.id"
        ];
        # No ExecStartPre here — the daemon already installed both packages
        # and this unit is ordered After it.
        # bun-installed bin shim has a node shebang — prefer it over
        # hand-building the node invocation.
        ExecStart = "%h/.bun/bin/pi-web-server";
      };
    };
  };
}
