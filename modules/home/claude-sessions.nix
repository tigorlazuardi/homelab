# Persistent zellij + claude-code sessions, owned by systemd --user (homeserver).
#
# Problem: projects run in zellij and are remote-controlled from claude.ai, but a
# reboot/crash lost them (plain `zellij` execute has no supervisor). Here each
# durable project is a `Type=simple`, `Restart=always` user service:
#
#   destroy/exit → service exits → systemd recreates a FRESH session.
#
# Durability is the *claude conversation*, not the zellij layout: on recreate,
# `claude --continue` resumes the prior conversation for that project dir. Any
# extra panes the user opened are expected to vanish — only claude is durable.
#
# Two Enter-snags are designed out:
#   1. resurrect prompt — launcher runs `zellij delete-session --force` first, so
#      no serialized/EXITED session is ever attached (always created fresh).
#   2. "command exited, press Enter to re-run" — the layout pane sets
#      `close_on_exit true`, so claude exiting closes the pane → session ends →
#      systemd restarts. No keypress needed anywhere.
#
# The ctrl+g management-mode + keymap legend behaviour comes from the existing
# ~/.config/zellij/config.kdl (locked default → Ctrl-g → normal shows the legend;
# then o→session (o,w = session-manager), p→pane). The layout below renders that
# legend via the status-bar plugin. Config.kdl is intentionally left unmanaged.
{
  pkgs,
  config,
  lib,
  ...
}:
let
  home = config.home.homeDirectory;

  # PATH for the units: bun global bin (claude-retry), the user profile (claude,
  # zellij, fish), and the system profile.
  userPath = "${home}/.bun/bin:/etc/profiles/per-user/homeserver/bin:/run/current-system/sw/bin:/usr/bin:/bin";

  # Durable sessions: friendly zellij/remote-control name → project dir (rel home).
  sessions = [
    { name = "Wallrus"; dir = "projects/wallrus"; }
    { name = "Commercelator"; dir = "projects/commercelator-template"; }
    { name = "Claude Retry Development"; dir = "projects/claude-retry"; }
    { name = "Bun Cloudflare Template"; dir = "projects/bun-cloudflare-template"; }
    { name = "Booth9"; dir = "projects/booth9"; }
    { name = "Telemetry JS Development"; dir = "projects/telemetry-js"; }
    { name = "Sittyba"; dir = "projects/sittyba"; }
    # config management: the homelab infra repo. ~/dotfiles is being archived
    # (reference only) → no session for it.
    { name = "Config Management"; dir = "homelab"; }
    { name = "Chezmoi"; dir = ".local/share/chezmoi"; }
    { name = "Visual Planner"; dir = "projects/visual-planner"; }
  ];

  slug = name: lib.toLower (lib.replaceStrings [ " " ] [ "-" ] name);

  # Resume-or-start claude, deriving the name from the zellij session it runs in,
  # so a single layout serves every session.
  claude-rc = pkgs.writeShellScriptBin "claude-rc" ''
    export PATH="${userPath}:$PATH"
    name="''${ZJ_SESSION:-''${ZELLIJ_SESSION_NAME:-claude}}"
    claude --continue --remote-control "$name" || claude --remote-control "$name"
  '';

  # Shared layout: bars top/bottom (legend), claude body pane that closes on exit.
  claudeLayout = pkgs.writeText "claude-layout.kdl" ''
    layout {
        default_tab_template {
            pane size=1 borderless=true {
                plugin location="zellij:tab-bar"
            }
            children
            pane size=2 borderless=true {
                plugin location="zellij:status-bar"
            }
        }
        pane {
            command "${claude-rc}/bin/claude-rc"
            close_on_exit true
        }
    }
  '';

  # One launcher per session: wipe stale session, then run zellij headless under a
  # PTY (script). The PTY is sized large so a human attaching later isn't capped
  # to a tiny viewport (zellij renders to the smallest attached client).
  #
  # Thundering-herd guard: when all units (re)start at once (reboot, or
  # `systemctl --user restart 'zellij-*'`), 9 zellij servers + claude spin up
  # together. A client can occasionally connect before its server registers the
  # named socket and then hang forever in hrtimer_nanosleep — a clean exit would
  # have let Restart=always recover, but a hang strands the session silently.
  # So we background zellij and watchdog it: if the session name hasn't appeared
  # in `list-sessions` within the window, kill it and exit non-zero so systemd
  # restarts cleanly. (Stagger via ExecStartPre below reduces how often we race.)
  launcher = s:
    pkgs.writeShellScript "zellij-${slug s.name}-launch" ''
      export PATH="${userPath}:$PATH"
      name=${lib.escapeShellArg s.name}
      zj=${pkgs.zellij}/bin/zellij
      "$zj" delete-session "$name" --force 2>/dev/null || true
      # NB: --layout with --session means "add a tab to an EXISTING session" and
      # errors ("There is no active session!") when none exists. Use
      # --new-session-with-layout to actually create a fresh named session.
      ${pkgs.util-linux}/bin/script -qfc \
        "stty rows 60 cols 250; exec \"$zj\" --session \"$name\" --new-session-with-layout ${claudeLayout}" \
        /dev/null &
      sp=$!
      # Watchdog: session must register within ~25s, else the client is wedged.
      registered=
      for _ in $(seq 1 25); do
        sleep 1
        if "$zj" list-sessions -s 2>/dev/null | grep -qxF "$name"; then
          registered=1; break
        fi
        kill -0 "$sp" 2>/dev/null || break   # script already died → let exit code flow
      done
      if [ -z "$registered" ] && ! "$zj" list-sessions -s 2>/dev/null | grep -qxF "$name"; then
        echo "watchdog: session '$name' never registered; killing for restart" >&2
        kill "$sp" 2>/dev/null || true
        exit 1
      fi
      wait "$sp"
    '';

  mkSessionService = i: s: lib.nameValuePair "zellij-${slug s.name}" {
    Unit.Description = "Persistent zellij + claude session: ${s.name}";
    Install.WantedBy = [ "default.target" ];
    Service = {
      Type = "simple";
      WorkingDirectory = "${home}/${s.dir}";
      # systemd --user units inherit no TERM; without it claude/zellij detect no
      # color support and emit plain text. The script(1) PTY makes isatty pass,
      # but color still needs TERM + COLORTERM. truecolor matches the bars/legend.
      Environment = [ "PATH=${userPath}" "TERM=xterm-256color" "COLORTERM=truecolor" ];
      Slice = "sessions.slice";
      # Stagger first-start by index so a mass (re)start / reboot doesn't spin up
      # all 9 zellij servers in the same instant (the client/server socket race
      # the watchdog guards against). Cheap; only delays the launch, not claude.
      ExecStartPre = "${pkgs.coreutils}/bin/sleep ${toString (i * 2)}";
      ExecStart = "${launcher s}";
      Restart = "always";
      RestartSec = 5;
    };
  };
in
{
  home.packages = [ claude-rc ];

  # CPU priority for ALL interactive zellij+claude sessions (+ retry daemon).
  # Global ceiling is user.slice CPUQuota=680% (see modules/cpu-budget.nix) — no
  # per-slice quota needed. CPUWeight determines share within homeserver's user
  # session; relative to media services it's governed by user-1000 vs user-1001
  # weights at the system level (coding gets ≈40% of user.slice when saturated).
  systemd.user.slices.sessions.Slice = {
    CPUWeight = "100"; # default weight; competes fairly within homeserver session
  };

  systemd.user.services = lib.listToAttrs (lib.imap0 mkSessionService sessions) // {
    # Claude Retry Monitor — NOT a zellij session. Foreground daemon that talks to
    # zellij over the CLI (zellij on PATH). Refresh to the newest published version
    # on every (re)start; ignore the upgrade if offline so it still starts.
    claude-retry = {
      Unit.Description = "Claude Retry Monitor (@tigorhutasuhut/claude-retry, always latest)";
      Install.WantedBy = [ "default.target" ];
      Service = {
        Type = "simple";
        WorkingDirectory = home;
        Environment = "PATH=${userPath}";
        ExecStartPre = "-${pkgs.bun}/bin/bun add -g @tigorhutasuhut/claude-retry@latest";
        ExecStart = "${home}/.bun/bin/claude-retry start";
        Slice = "sessions.slice";
        Restart = "always";
        RestartSec = 10;
      };
    };
  };
}
