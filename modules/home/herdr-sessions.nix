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
  inputs,
  ...
}:
let
  home = config.home.homeDirectory;

  herdr = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;

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
    { name = "Wallrus"; dir = "projects/wallrus"; }
    { name = "Commercelator"; dir = "projects/commercelator-template"; enable = false; }
    { name = "Claude Retry Development"; dir = "projects/claude-retry"; }
    { name = "Bun Cloudflare Template"; dir = "projects/bun-cloudflare-template"; enable = false; }
    { name = "Booth9"; dir = "projects/booth9"; enable = false; }
    { name = "Telemetry JS Development"; dir = "projects/telemetry-js"; enable = false; }
    { name = "Sittyba"; dir = "projects/sittyba"; }
    # config management: the homelab infra repo.
    { name = "Config Management"; dir = "homelab"; }
    { name = "Chezmoi"; dir = ".local/share/chezmoi"; }
    { name = "Visual Planner"; dir = "projects/visual-planner"; }
  ];

  enabledSessions = lib.filter (s: s.enable or true) sessions;

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

  # Idempotent provisioner: for each enabled session, ensure a workspace labeled
  # s.name exists; when creating one, start a claude pane in it and close the
  # root shell pane `workspace create` auto-spawns (claude fills the workspace,
  # zellij-layout parity). Existing workspaces are left untouched (herdr's own
  # snapshot restore owns those). JSON paths verified live against v0.7.1.
  provision = pkgs.writeShellScript "herdr-provision" ''
    set -u
    export PATH="${userPath}:$PATH"
    jq=${pkgs.jq}/bin/jq

    # Wait for the daemon to accept commands. NB: `status server` exits 0 even
    # when the server is down — parse the output, don't trust the exit code.
    up() { herdr status server 2>/dev/null | grep -q '^status: running'; }
    for _ in $(seq 1 30); do
      up && break
      sleep 1
    done
    if ! up; then
      echo "herdr server never became ready" >&2
      exit 1
    fi

    existing=$(herdr workspace list 2>/dev/null | $jq -r '.result.workspaces[].label // empty' || true)

    ensure() { # $1=label $2=cwd
      if printf '%s\n' "$existing" | grep -qxF "$1"; then
        echo "workspace '$1' present — skip"
        return 0
      fi
      echo "creating workspace '$1' at $2"
      resp=$(herdr workspace create --cwd "$2" --label "$1" --no-focus)
      ws=$(printf '%s' "$resp" | $jq -r '.result.workspace.workspace_id // empty')
      root=$(printf '%s' "$resp" | $jq -r '.result.root_pane.pane_id // empty')
      if [ -z "$ws" ]; then
        echo "failed to create workspace '$1': $resp" >&2
        return 1
      fi
      herdr agent start claude --workspace "$ws" --cwd "$2" --no-focus \
        -- ${claude-hr}/bin/claude-hr "$1" || return 1
      [ -n "$root" ] && herdr pane close "$root"
      return 0
    }

    rc=0
    ${lib.concatMapStrings (s: ''
      ensure ${lib.escapeShellArg s.name} ${lib.escapeShellArg "${home}/${s.dir}"} || rc=1
    '') enabledSessions}
    exit $rc
  '';
in
{
  home.packages = [
    herdr
    claude-hr
  ];

  # Declarative base config. NB: home-manager symlinks this read-only — herdr's
  # settings UI / `herdr config reset-keys` can't write it; edit here instead.
  xdg.configFile."herdr/config.toml".text = ''
    # Managed by nix (modules/home/herdr-sessions.nix) — edit there.
    onboarding = false

    [update]
    # Binary is nix-managed (flake input, pinned tag) — no self-update nagging.
    version_check = false

    [ui.sound]
    # Headless host: no audio sink; sound is the attaching client's business.
    enabled = false

    [ui.toast]
    # Escape-sequence notifications to the outer terminal — works over SSH,
    # the local terminal (ghostty/kitty/wezterm/iterm2) owns the popup.
    delivery = "terminal"
  '';

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

    # Provision workspaces after every daemon (re)start. PartOf propagates a
    # herdr-server restart into a re-run of this oneshot (After alone only
    # orders the initial boot).
    herdr-sessions = {
      Unit = {
        Description = "Provision durable claude workspaces in herdr";
        After = [ "herdr-server.service" ];
        Requires = [ "herdr-server.service" ];
        PartOf = [ "herdr-server.service" ];
      };
      Install.WantedBy = [ "default.target" ];
      Service = {
        Type = "oneshot";
        Environment = [ "PATH=${userPath}" ];
        ExecStart = "${provision}";
        Slice = "sessions.slice";
      };
    };
  };
}
