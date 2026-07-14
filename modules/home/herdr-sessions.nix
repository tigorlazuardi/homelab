# Persistent herdr + claude-code sessions, owned by systemd --user (homeserver).
# Replaces the zellij-per-session design (git: modules/home/claude-sessions.nix).
#
# Architecture: ONE herdr daemon (`herdr server`, herdr-server.service) owns every
# pane; a oneshot provisioner (herdr-sessions.service) ensures each durable project
# has a workspace with a claude pane. Attach paths:
#   * local/SSH:  `herdr` on the host (tmux-style)
#   * remote:     `herdr --remote <ssh-host>` from a laptop — thin client over SSH,
#                 bridges the LOCAL clipboard incl. image paste. No TCP listener on
#                 the host (unix socket only), so the guard is SSH itself (tailscale
#                 / LAN). This replaces zellij-web + its public vhost + token.
#
# Durability layers:
#   1. daemon restart → herdr's session snapshot restores workspaces/tabs/panes and
#      `[session] resume_agents_on_restore` (default on) resumes claude panes into
#      their native conversations — REQUIRES the claude integration hooks, see
#      one-time setup below.
#   2. claude exiting inside a live pane → the pane runs `claude-hr`, a
#      resume-or-start loop, so the pane never dies with claude.
#   3. missing workspace (first boot, pane closed by hand) → the provisioner
#      recreates it on the next herdr-server (re)start.
#   NOT covered: claude dead inside a pane that survived a native restore (no loop
#   wrapper there). Ongoing healing is the claude-retry herdr port (todo.txt).
#
# One-time setup after first switch (as homeserver):
#   herdr integration install claude   # authoritative agent state + native session
#                                      # refs for resume (writes claude hooks config)
# The integration is imperative user-level config, like zellij's config.kdl was.
{
  pkgs,
  config,
  lib,
  osConfig,
  ...
}:
let
  home = config.home.homeDirectory;

  # herdr binary from nixpkgs via the home-manager programs.herdr module
  # (enabled below). Was the `herdr` flake input; now nixpkgs-managed.
  herdr = config.programs.herdr.package;

  # Grafana MCP token (see modules/users.nix). With the single-daemon model every
  # pane inherits the server env, so the token is loaded server-wide instead of
  # per-session as under zellij. Same user, single-operator host — acceptable
  # scope; claude's .mcp.json expands GRAFANA_SERVICE_ACCOUNT_TOKEN where used.
  grafanaMcpEnvFile = osConfig.sops.secrets."grafana-mcp.env".path;

  # PATH for the daemon (panes are its children and inherit it): bun global bin,
  # the user profile (claude, fish), and the system profile.
  userPath = "${home}/.bun/bin:/etc/profiles/per-user/homeserver/bin:/run/current-system/sw/bin:/usr/bin:/bin";

  # Durable sessions: workspace label → project dir (rel home). `enable = false`
  # keeps the entry but skips provisioning (existing workspace is left alone —
  # close it by hand to free RAM; flip back to re-provision). Disabled set chosen
  # during the RAM-pressure review.
  sessions = [
    {
      name = "Wallrus";
      dir = "projects/wallrus";
      enable = false;
    }
    {
      name = "Commercelator";
      dir = "projects/commercelator-template";
      enable = false;
    }
    # herdr port of claude-retry (the zellij-CLI original is retired; see todo.txt)
    {
      name = "Herdr Claude Retry Development";
      dir = "projects/herdr-claude-retry";
      enable = false;
    }
    {
      name = "Bun Cloudflare Template";
      dir = "projects/bun-cloudflare-template";
      enable = false;
    }
    {
      name = "Booth9";
      dir = "projects/booth9";
      enable = false;
    }
    {
      name = "Telemetry JS Development";
      dir = "projects/telemetry-js";
      enable = false;
    }
    {
      name = "Sittyba";
      dir = "projects/sittyba";
      enable = false;
    }
    # config management: the homelab infra repo.
    {
      name = "Config Management";
      dir = "homelab";
    }
    {
      name = "Chezmoi";
      dir = ".local/share/chezmoi";
      enable = false;
    }
    {
      name = "Plandeck Development";
      dir = "projects/visual-planner";
      enable = false;
    }
    # Pi (not claude) harness; repo cloned via git ssh on first provision if absent.
    {
      name = "Ring Road";
      dir = "projects/ring-road";
      harness = "pi";
      repo = "git@github.com:tigorlazuardi/ring-road.git";
    }
    {
      name = "Herdr Sheepdog";
      dir = "projects/herdr-sheepdog";
      harness = "pi";
    } # local git init, no remote
    {
      name = "Herdr Web TUI";
      dir = "projects/herdr-web-tui";
      harness = "pi";
      repo = "git@github.com:tigorlazuardi/herdr-web-tui.git";
    }
    {
      name = "Sekolah Sinar Kasih";
      dir = "projects/sekolah-sinar-kasih";
      harness = "pi";
      enable = false;
    } # local git init, no remote
    {
      name = "NixOS Switch Approval Telegram Portal";
      dir = "projects/nixos-switch-approval-telegram-portal";
      harness = "pi";
      repo = "git@github.com:tigorlazuardi/nixos-switch-approval-telegram-portal.git";
    }
    # pi's own config dir (~/.pi) — manage pi config with pi itself. Local, no remote.
    {
      name = "Pi Configuration";
      dir = ".pi";
      harness = "pi";
    }
    {
      name = "Pi Sheepdog";
      dir = "projects/pi-sheepdog";
      harness = "pi";
    } # local git init, no remote
  ];

  enabledSessions = lib.filter (s: s.enable or true) sessions;

  # Agent names are unique SERVER-WIDE in herdr (a second `agent start claude`
  # fails with agent_name_taken) — so each session's agent is named by its
  # slugged workspace label, not "claude". Screen detection / the integration
  # still identify the agent TYPE as claude; the name is just identity.
  slug = name: lib.toLower (lib.replaceStrings [ " " ] [ "-" ] name);

  # Per-session coding harness → the pane's resume-or-start wrapper. Default
  # claude; `harness = "pi"` selects the pi wrapper (Ring Road). pi-hr is defined
  # below — fine, `let` bindings are recursive.
  harnessBin =
    s: if (s.harness or "claude") == "pi" then "${pi-hr}/bin/pi-hr" else "${claude-hr}/bin/claude-hr";

  # Resume-or-start claude, looping so the pane survives claude exiting (parity
  # with the old zellij close_on_exit + systemd Restart=always semantics: exit →
  # fresh claude resuming the same conversation). Workspace label comes in as $1.
  claude-hr = pkgs.writeShellScriptBin "claude-hr" ''
    export PATH="${userPath}:$PATH"
    name="''${1:-claude}"
    while true; do
      claude --continue --remote-control "$name" || claude --remote-control "$name"
      echo "claude exited — restarting in 3s (ctrl-c to get a shell)" >&2
      sleep 3 || exec ''${SHELL:-bash}
    done
  '';

  # Pi coding-agent harness (Ring Road). pi has no --remote-control (claude-only);
  # `pi --continue` resumes the latest session in the pane cwd. Same crash-restart
  # loop as claude-hr so the pane survives pi exiting. herdr's native
  # resume-on-restore is claude-specific — pi panes rely on this loop + pi's own
  # session store instead.
  pi-hr = pkgs.writeShellScriptBin "pi-hr" ''
    export PATH="${userPath}:$PATH"
    while true; do
      pi --continue || pi
      echo "pi exited — restarting in 3s (ctrl-c to get a shell)" >&2
      sleep 3 || exec ''${SHELL:-bash}
    done
  '';

  # ── systemd-owned session lifecycle (replaces oneshot + snapshot restore) ─────
  # Each durable session is its OWN Type=simple, Restart=always user service. The
  # pair of scripts below is the ExecStartPre/ExecStart body, parameterized by
  # positional args so one script serves every session.

  # Shared daemon-ready wait — `status server` exits 0 even when down, so parse it.
  waitDaemon = ''
    up() { herdr status server 2>/dev/null | grep -q '^status: running'; }
    for _ in $(seq 1 30); do up && break; sleep 1; done
    if ! up; then echo "herdr server never became ready" >&2; exit 1; fi
  '';

  # ExecStartPre — $1=label $2=cwd $3=repo(optional). REFRESH: destroy any
  # workspace carrying this label (there may be a stale one herdr's snapshot
  # restored, or a remnant from the pane the user just destroyed), then clone the
  # repo if the project dir is missing. Runs before every (re)start.
  sessionPre = pkgs.writeShellScript "herdr-session-pre" ''
    set -u
    export PATH="${userPath}:$PATH"
    jq=${pkgs.jq}/bin/jq
    label=$1 cwd=$2 repo=''${3:-}
    ${waitDaemon}
    herdr workspace list 2>/dev/null \
      | $jq -r --arg l "$label" '.result.workspaces[]? | select(.label==$l) | .workspace_id' \
      | while read -r ws; do
          [ -n "$ws" ] || continue
          echo "destroying stale workspace '$label' ($ws)"
          herdr workspace close "$ws" || true
        done
    if [ -n "$repo" ] && [ ! -d "$cwd/.git" ]; then
      echo "cloning $repo -> $cwd"
      git clone "$repo" "$cwd" || { echo "clone failed for '$label'" >&2; exit 1; }
    fi
    exit 0
  '';

  # ExecStart — $1=label $2=agent-name $3=cwd $4=harness-cmd. Create the workspace
  # fresh (so the full agent argv, incl. --remote-control via the harness, always
  # applies), start the agent pane, close the auto-spawned root shell pane, then
  # BLOCK watching the agent. When it vanishes (user destroyed the space/pane to
  # reload the harness), exit so Restart=always remakes it. claude-hr/pi-hr still
  # wrap the agent, so an in-pane claude/pi crash heals without tearing the space.
  sessionRun = pkgs.writeShellScript "herdr-session-run" ''
    set -u
    export PATH="${userPath}:$PATH"
    jq=${pkgs.jq}/bin/jq
    label=$1 name=$2 cwd=$3 harness=$4
    ${waitDaemon}
    echo "creating workspace '$label' at $cwd"
    resp=$(herdr workspace create --cwd "$cwd" --label "$label" --no-focus)
    ws=$(printf '%s' "$resp" | $jq -r '.result.workspace.workspace_id // empty')
    root=$(printf '%s' "$resp" | $jq -r '.result.root_pane.pane_id // empty')
    if [ -z "$ws" ]; then echo "failed to create workspace '$label': $resp" >&2; exit 1; fi
    herdr agent start "$name" --workspace "$ws" --cwd "$cwd" --no-focus -- "$harness" "$label" \
      || { echo "agent start failed for '$label'" >&2; exit 1; }
    [ -n "$root" ] && herdr pane close "$root" || true

    # Grace: wait for the agent to register (up to ~20s) before treating a missing
    # agent as destroyed, else a slow start would drop us straight into a restart.
    for _ in $(seq 1 20); do herdr agent get "$name" >/dev/null 2>&1 && break; sleep 1; done

    # Watch: block while the agent/pane lives; exit when it's gone. `agent get`
    # exits non-zero (agent_not_found) once the pane is destroyed.
    while herdr agent get "$name" >/dev/null 2>&1; do sleep 4; done
    echo "agent '$name' gone — exiting so systemd remakes the space" >&2
    exit 0
  '';
in
{
  # herdr binary comes from nixpkgs via the home-manager module.
  programs.herdr.enable = true;
  programs.herdr.settings = {
    onboarding = false;
    # Restore OFF. herdr's snapshot restore rebuilds a pane but does NOT carry the
    # agent's start argv (notably `--remote-control <name>`), so a restored claude
    # pane loses its remote-control identity. systemd owns the session lifecycle
    # instead — one herdr-session-<slug>.service per durable session (below).
    session.resume_agents_on_restore = false;
    # Binary is nix-managed (flake input, pinned tag) — no self-update nagging.
    update.version_check = false;
    # Headless host: no audio sink; sound is the attaching client's business.
    ui.sound.enabled = false;
    # Escape-sequence notifications to the outer terminal — works over SSH,
    # the local terminal (ghostty/kitty/wezterm/iterm2) owns the popup.
    ui.toast.delivery = "terminal";
  };

  home.packages = [
    claude-hr
    pi-hr
  ];

  # CPU priority for ALL interactive claude sessions. Global ceiling is user.slice
  # CPUQuota=680% (see modules/cpu-budget.nix); CPUWeight governs share within
  # homeserver's user session (coding tier ≈40% of user.slice when saturated).
  systemd.user.slices.sessions.Slice = {
    CPUWeight = "100";
  };

  systemd.user.services = {
    # The daemon. Every pane (all claude sessions) is a child of this unit, so
    # Slice/env here apply to all of them — one knob for the whole coding tier.
    herdr-server = {
      Unit.Description = "herdr server (terminal workspace daemon for claude sessions)";
      Install.WantedBy = [ "default.target" ];
      Service = {
        Type = "simple";
        WorkingDirectory = home;
        # systemd --user units inherit no TERM; herdr allocates pane PTYs itself
        # but claude still reads TERM/COLORTERM for color support.
        Environment = [
          "PATH=${userPath}"
          "TERM=xterm-256color"
          "COLORTERM=truecolor"
        ];
        EnvironmentFile = [ grafanaMcpEnvFile ];
        ExecStart = "${herdr}/bin/herdr server";
        Slice = "sessions.slice";
        Restart = "always";
        RestartSec = 5;
      };
    };

  }
  # One Type=simple service per durable session. After+Requires+PartOf herdr-server
  # so a daemon (re)start propagates into a full teardown+remake of every session
  # (PartOf restarts the unit; its ExecStartPre destroys the snapshot-restored
  # workspace and ExecStart recreates it fresh). Restart=always is what remakes a
  # space the user destroyed to reload the harness.
  // (lib.listToAttrs (
    map (s: {
      name = "herdr-session-${slug s.name}";
      value = {
        Unit = {
          Description = "herdr session: ${s.name}";
          After = [ "herdr-server.service" ];
          Requires = [ "herdr-server.service" ];
          PartOf = [ "herdr-server.service" ];
        };
        Install.WantedBy = [ "default.target" ];
        Service = {
          Type = "simple";
          Environment = [
            "PATH=${userPath}"
            "TERM=xterm-256color"
            "COLORTERM=truecolor"
          ];
          ExecStartPre = "${sessionPre} ${lib.escapeShellArg s.name} ${
            lib.escapeShellArg "${home}/${s.dir}"
          } ${lib.escapeShellArg (s.repo or "")}";
          ExecStart = "${sessionRun} ${lib.escapeShellArg s.name} ${lib.escapeShellArg (slug s.name)} ${
            lib.escapeShellArg "${home}/${s.dir}"
          } ${lib.escapeShellArg (harnessBin s)}";
          Slice = "sessions.slice";
          Restart = "always";
          RestartSec = 5;
        };
      };
    }) enabledSessions
  ));
}
