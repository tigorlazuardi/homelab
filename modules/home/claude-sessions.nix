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
    { name = "Dotfiles"; dir = "dotfiles"; }
    { name = "Chezmoi"; dir = ".local/share/chezmoi"; }
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
  launcher = s:
    pkgs.writeShellScript "zellij-${slug s.name}-launch" ''
      export PATH="${userPath}:$PATH"
      name=${lib.escapeShellArg s.name}
      ${pkgs.zellij}/bin/zellij delete-session "$name" --force 2>/dev/null || true
      exec ${pkgs.util-linux}/bin/script -qfc \
        "stty rows 60 cols 250; exec ${pkgs.zellij}/bin/zellij --session \"$name\" --layout ${claudeLayout}" \
        /dev/null
    '';

  mkSessionService = s: lib.nameValuePair "zellij-${slug s.name}" {
    Unit.Description = "Persistent zellij + claude session: ${s.name}";
    Install.WantedBy = [ "default.target" ];
    Service = {
      Type = "simple";
      WorkingDirectory = "${home}/${s.dir}";
      Environment = "PATH=${userPath}";
      ExecStart = "${launcher s}";
      Restart = "always";
      RestartSec = 5;
    };
  };
in
{
  home.packages = [ claude-rc ];

  systemd.user.services = lib.listToAttrs (map mkSessionService sessions) // {
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
        Restart = "always";
        RestartSec = 10;
      };
    };
  };
}
