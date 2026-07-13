# bareksa-box — systemd-nspawn NixOS container for the office VPN (netbird +
# OpenVPN), reachable over its own Tailscale node, with rootless podman nested
# inside. See plans/bareksa-box/SPEC.mdx for the full design + decisions.
#
# Pivoted from Incus: virtualisation.incus asserts networking.nftables.enable
# whenever the firewall is on, and this host's wireguard.nix uses raw iptables.
# systemd-nspawn (native NixOS `containers.*`) has no such requirement and keeps
# the host on iptables untouched.
#
# VPN credentials are NOT configured here (out of scope, user-manual):
#   sudo nixos-container root-login bareksa-box   # or: sudo machinectl shell bareksa-box
#   tailscale up                                  # interactive auth, joins tailnet
#   # then SSH in over tailscale and configure netbird / openvpn manually.
{ lib, inputs, ... }:
let
  # Same WAN interface wireguard.nix NATs through — reuse it so container
  # egress rides the existing iptables MASQUERADE path.
  externalInterface = "eth0";
in
{
  containers.bareksa-box = {
    autoStart = true;

    # Fresh /24, avoids wireguard's 10.0.0.0/24 and the tailnet's 100.64.0.0/10.
    privateNetwork = true;
    hostAddress = "10.100.0.1";
    localAddress = "10.100.0.2";

    # /dev/net/tun for netbird/openvpn to create tunnel interfaces.
    enableTun = true;

    # VPN route setup inside the container's own netns.
    additionalCapabilities = [
      "CAP_NET_ADMIN"
      "CAP_NET_RAW"
    ];

    # Pass flake inputs into the guest eval so it can pull claude-code / pi
    # (llm-agents) and herdr from the same pins the host uses.
    specialArgs = { inherit inputs; };

    config =
      { pkgs, ... }:
      let
        agents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
        herdr = pkgs.herdr; # nixpkgs (was the herdr flake input)

        # PATH for the herdr daemon (its panes inherit it): claude/pi/node/git
        # all land in the system profile via environment.systemPackages.
        herdrUserPath = "/run/wrappers/bin:/run/current-system/sw/bin";

        # herdr-claude-retry: auto-resumes rate-limited claude panes. Same npm
        # tarball as the host (modules/home/herdr-claude-retry.nix) — prebuilt
        # dist/, zero runtime deps, run with node. Bump: version + hash.
        herdr-claude-retry = pkgs.stdenvNoCC.mkDerivation {
          pname = "herdr-claude-retry";
          version = "0.1.7";
          src = pkgs.fetchurl {
            url = "https://registry.npmjs.org/@tigorhutasuhut/herdr-claude-retry/-/herdr-claude-retry-0.1.7.tgz";
            hash = "sha256-h4xv72wgGDkN3p+LRJQUQ9MFx0TbLik9Kgr6t656dGM=";
          };
          installPhase = ''
            mkdir -p $out/lib
            cp -r . $out/lib
          '';
        };
      in
      {
        # Own tailnet node — this is the SSH ingress path (bootstrap: root-login
        # once from the host, `tailscale up` interactively, then SSH over tailnet).
        services.tailscale.enable = true;

        services.openssh.enable = true;

        # tigor has no password (SSH-key-only login), so default
        # wheelNeedsPassword would make `sudo` prompt for a password that
        # doesn't exist → unusable. Access is already gated by SSH keys over the
        # tailnet, so let wheel sudo without one. (Alternative: a sops
        # hashedPasswordFile — not worth it for a single-operator, key-only box.)
        security.sudo.wheelNeedsPassword = false;

        # Keep tailscale WINNING over a full-tunnel office VPN. Once the user
        # brings up openvpn/netbird with redirect-gateway, they hijack the
        # MAIN-table default route. Tailscale marks its OWN uplink packets
        # (control + DERP relays + encrypted peer traffic) with fwmark 0x80000
        # and, by its own rule `5230: from all fwmark 0x80000 lookup main`,
        # those then follow the hijacked default straight into the office tunnel
        # — tailscale loses its control/DERP path, the tailnet drops, and SSH
        # over tailscale (this box's ONLY ingress) dies with it.
        #
        # Fix (policy routing): a private table (52814) whose default is the
        # box's REAL uplink — the current non-tunnel default (auto-detected gw +
        # dev, i.e. the nspawn host gateway), which openvpn never touches — plus
        # an ip rule at priority 5200 (ABOVE
        # tailscale's own 5230) sending tailscale-marked packets there. So
        # tailscale's uplink always egresses the clean path no matter what
        # openvpn does to `main`; every OTHER (unmarked) app on the box still
        # rides the full tunnel as intended. Inbound SSH (dest 100.64.0.0/10)
        # already rides tailscale's own table-52 rule and is unaffected.
        #
        # PartOf tailscaled → re-applied whenever tailscale restarts (which
        # reinstalls its 52xx rules); our 5200 rule sits outside tailscale's
        # managed 5210-5270 range so tailscaled leaves it alone.
        systemd.services.tailscale-uplink-guard = {
          description = "Pin tailscale uplink outside a full-tunnel VPN (policy routing)";
          after = [
            "tailscaled.service"
            "network.target"
          ];
          partOf = [ "tailscaled.service" ];
          wantedBy = [
            "multi-user.target"
            "tailscaled.service"
          ];
          path = [
            pkgs.iproute2
            pkgs.coreutils
            pkgs.gnused
            pkgs.gnugrep
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            set -u
            tbl=52814
            # Clean uplink = the current NON-tunnel default route. AUTO-DETECTED
            # (gw + dev) so we never hardcode the guest iface name — hardcoding
            # `host0` was wrong and left the guard skipping = zero protection =
            # SSH dropped when openvpn came up. Retry briefly for the boot race
            # where the default route isn't installed yet.
            def=""
            for _ in $(seq 1 10); do
              def=$(ip route show default 2>/dev/null | grep -vE 'dev (tun|tap)[0-9]*' | head -1)
              [ -n "$def" ] && break
              sleep 1
            done
            if [ -z "$def" ]; then
              echo "tailscale-uplink-guard: no non-tunnel default route, skipping" >&2
              exit 0
            fi
            gw=$(printf '%s\n' "$def" | sed -n 's/.* via \([0-9.]*\).*/\1/p')
            dev=$(printf '%s\n' "$def" | sed -n 's/.* dev \([^ ]*\).*/\1/p')
            if [ -z "$gw" ] || [ -z "$dev" ]; then
              echo "tailscale-uplink-guard: cannot parse default route ($def), skipping" >&2
              exit 0
            fi
            # Clean uplink table — independent of whatever openvpn does to main.
            ip route replace default via "$gw" dev "$dev" table "$tbl"
            # Route tailscale-marked (0x80000) traffic through it, above
            # tailscale's own `lookup main` rule (5230). Idempotent.
            ip rule del priority 5200 2>/dev/null || true
            ip rule add priority 5200 fwmark 0x80000/0xff0000 table "$tbl"
            echo "tailscale-uplink-guard: fwmark 0x80000 -> table $tbl (default via $gw dev $dev)" >&2
          '';
          preStop = ''
            ${pkgs.iproute2}/bin/ip rule del priority 5200 2>/dev/null || true
          '';
        };

        # netbird/openvpn = packages only, unconfigured (user supplies creds
        # manually). Coding env: claude-code + pi (llm-agents) + herdr binary,
        # with node/git/gh runtimes. Neovim binary via programs.neovim below.
        environment.systemPackages =
          (with pkgs; [
            netbird
            openvpn
            nodejs # claude-code runtime
            # common dev tooling (mirrors modules/cli.nix + dev.nix)
            git
            gh
            glab # GitLab CLI (office repos are on GitLab)
            curl
            wget
            unzip
            ripgrep
            fd
            fzf
            jq
            tree
            gnumake
            gcc
            # modern CLI (bat/eza/zoxide already wired via programs below)
            bat
            eza
            btop
            duf
            dust
            delta
            tldr
            yazi
            just
            mise # runtime/tool version manager
            oscclip # osc52-copy/osc52-paste — clipboard over terminal escape (SSH/herdr-safe)
          ])
          ++ [
            agents.claude-code
            agents.pi
            herdr
          ];

        # Office OpenVPN (full-tunnel). The config file + inline credentials live
        # ON the box at /etc/openvpn/office.ovpn — NOT in this public repo. This
        # only wires the systemd unit + DNS handling.
        #
        # Root cause of "connected but no name resolution": a manual
        # `openvpn --config ...` never applied the server-PUSHED DNS, so once
        # redirect-gateway took the default route, the box had no working
        # resolver under the tunnel. `updateResolvConf = true` plugs openvpn's
        # pushed DNS into the box's resolvconf (openresolv — the same stack
        # tailscale MagicDNS already writes), so both coexist. It also injects
        # the --up/--down script + script-security automatically; the .ovpn must
        # therefore NOT carry its own --up/--down lines.
        #
        # autoStart = FALSE deliberately — do NOT put openvpn in the boot
        # transaction. The NixOS module runs openvpn as `Type=notify`, which only
        # signals systemd "started" after the tunnel fully connects
        # (`Initialization Sequence Completed`). As a boot-time (multi-user.target)
        # unit that meant: guest boot blocks on openvpn's start job → the nspawn
        # container never signals "Ready" → the host `container@bareksa-box`
        # hits its start timeout and RESTART-LOOPS the whole container (observed:
        # NRestarts climbing, container stuck `activating`). openvpn is famously
        # bad at this. Instead we start it POST-boot via a timer (below).
        services.openvpn.servers.office = {
          config = "config /etc/openvpn/office.ovpn";
          updateResolvConf = true;
          autoStart = false;
        };

        # Bound + reorder the office VPN unit (the module names it openvpn-office).
        systemd.services."openvpn-office" = {
          after = [
            "tailscaled.service"
            "tailscale-uplink-guard.service"
          ];
          wants = [
            "tailscaled.service"
            "tailscale-uplink-guard.service"
          ];
          serviceConfig = {
            # Type=exec, NOT the module's notify: "started" = process is running,
            # not "tunnel is up". openvpn retries the connection itself
            # (resolv-retry infinite) — we never want systemd to sit in
            # `activating` waiting for a tunnel, nor Restart-loop when the office
            # server is briefly unreachable.
            Type = lib.mkForce "exec";
            # Even started post-boot by the timer, gate on tailscale actually
            # being Running before openvpn's redirect-gateway touches the route
            # table. At boot tailscale reconnects asynchronously and only marks
            # its packets (fwmark 0x80000) once its netfilter is fully up; if
            # openvpn hijacks the default first, the in-flight tailscale handshake
            # isn't marked yet → hits `main` → into the office tunnel → blocked →
            # tailscale never comes up, never marks → deadlock (SSH ingress dead).
            # Because openvpn is out of the boot transaction, this wait no longer
            # gates the container's Ready signal. Capped so it never hangs forever.
            ExecStartPre = pkgs.writeShellScript "wait-tailscale-running" ''
              for _ in $(${pkgs.coreutils}/bin/seq 1 60); do
                state=$(${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null \
                  | ${pkgs.jq}/bin/jq -r '.BackendState // empty' 2>/dev/null)
                [ "$state" = "Running" ] && exit 0
                ${pkgs.coreutils}/bin/sleep 1
              done
              echo "wait-tailscale-running: not Running after 60s, starting openvpn anyway" >&2
              exit 0
            '';
            # Bound shutdown: openvpn's SIGTERM stop (down-script + explicit-exit-
            # notify to the server) can hang toward systemd's 90s default, and the
            # nspawn container's poweroff waits on it — which in turn blocks a host
            # `nixos-rebuild switch`. A normal stop finishes well under a second
            # (local resolvconf down-script + one UDP notify), so cap hard at 3s;
            # past that SIGKILL — the tunnel is stateless, a hard kill is safe.
            TimeoutStopSec = "3s";
          };
        };

        # Autostart openvpn POST-boot via a timer, NOT via multi-user.target.
        # timers.target arms instantly (the timer unit doesn't wait on openvpn),
        # so the guest reaches Ready without ever blocking on the tunnel; the
        # timer then fires ~20s later and starts openvpn-office — by which point
        # boot is done and tailscale is (or is about to be) Running.
        systemd.timers."openvpn-office-autostart" = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "20s";
            AccuracySec = "1s";
            Unit = "openvpn-office.service";
          };
        };

        # Neovim (no config — user manages it manually), mirroring the host's
        # modules/neovim.nix defaults.
        programs.neovim = {
          enable = true;
          viAlias = true;
          vimAlias = true;
          defaultEditor = true;
        };

        # Run unpatched dynamic binaries (mise-installed toolchains, downloaded
        # binaries, LSPs) — mirrors modules/nix-ld.nix.
        programs.nix-ld.enable = true;
        services.envfs.enable = true;
        programs.appimage = {
          enable = true;
          binfmt = true;
        };

        # direnv + nix-direnv — mirrors modules/direnv.nix.
        programs.direnv = {
          enable = true;
          nix-direnv.enable = true;
        };

        # herdr coding-session daemon + auto-retry, mirroring the host
        # (modules/home/herdr-sessions.nix + herdr-claude-retry.nix). Declared as
        # system-level systemd.user services (no home-manager in this guest).
        # NOTE: the host's session PROVISIONER is intentionally NOT copied — it
        # provisions host-specific project workspaces that don't exist here; run
        # sessions by hand via `herdr` instead. Needs linger (below) to run
        # without an active login.
        # System-level systemd.user schema (lowercase description/wantedBy/
        # serviceConfig) — NOT the home-manager Unit/Service/Install schema the
        # host uses.
        systemd.user.slices.sessions.sliceConfig.CPUWeight = "100";
        systemd.user.services.herdr-server = {
          description = "herdr server (terminal workspace daemon for coding sessions)";
          wantedBy = [ "default.target" ];
          environment = {
            # Override the stock user-unit PATH so herdr can spawn claude/pi/node
            # from the system profile. sw/bin already carries coreutils et al.
            PATH = lib.mkForce herdrUserPath;
            TERM = "xterm-256color";
            COLORTERM = "truecolor";
          };
          serviceConfig = {
            Type = "simple";
            WorkingDirectory = "%h";
            ExecStart = "${herdr}/bin/herdr server";
            Slice = "sessions.slice";
            Restart = "always";
            RestartSec = 5;
          };
        };
        systemd.user.services.herdr-claude-retry = {
          description = "Auto-resume rate-limited claude panes in herdr";
          after = [ "herdr-server.service" ];
          requires = [ "herdr-server.service" ];
          partOf = [ "herdr-server.service" ];
          wantedBy = [ "default.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.nodejs}/bin/node ${herdr-claude-retry}/lib/dist/cli.js start";
            WorkingDirectory = "%h";
            Slice = "sessions.slice";
            Restart = "always";
            RestartSec = 5;
          };
        };

        # Fish shell mirroring the host (modules/fish.nix), minus the host-only
        # `srv` helper (no srv user in this box).
        programs.fish = {
          enable = true;
          interactiveShellInit = ''
            set fish_greeting # Disable greeting
            ${pkgs.mise}/bin/mise activate fish | source
            # fzf fish keybindings: ctrl-t (files), ctrl-r (history), alt-c (cd).
            ${pkgs.fzf}/bin/fzf --fish | source
          '';
          shellAliases = {
            ls = "eza -la";
            cat = "bat";
          };
        };
        programs.zoxide = {
          enable = true;
          flags = [
            "--cmd cd"
            "--hook prompt"
          ];
        };

        # Nested rootless podman workloads, egress via whatever VPN owns the
        # box's default route. Nesting behavior (userns/cgroup delegation) is a
        # validate-live item per SPEC — defaults enabled here, revisit if
        # rootless podman refuses to start inside nspawn.
        virtualisation.podman = {
          enable = true;
          dockerCompat = true;
          defaultNetwork.settings.dns_enabled = true;
        };

        # SSH-ready login user `tigor` (the operator), same authorized key set as
        # modules/users.nix.
        users.users.tigor = {
          isNormalUser = true;
          extraGroups = [ "wheel" ];
          shell = pkgs.fish;
          # Run herdr-server + herdr-claude-retry without an active login.
          linger = true;
          openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPO1aSG3/1vrgEPgK038tZ8+ipz3gZqr9hRT0JUteJXY tigor@fort"
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB/dGHD56+3qsLhUvmG4GeN8JrpYw7oGt0iQT+WkZzFu tigor@nexus"
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGUdNT+Pr015Li6Jp9cb1vCghd2C8EnecYwSC98qQCxl tigor@envy"
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN9ZOi6U8vMBhXr7YcV76we8r8CgmPQ4JWd06fGNok23 tigorhutasuhut@Tigors-MacBook-Pro.local"
          ];
        };

        # Minimal — tailnet ingress (SSH) is the only expected inbound path.
        networking.firewall.enable = true;
        networking.firewall.allowedTCPPorts = [ 22 ];

        # Timezone + locale mirror the host (configuration.nix + modules/locale.nix):
        # en_US.UTF-8 base, id_ID.UTF-8 for the LC_* formatting categories, and
        # enableAllTerminfo so SSH from ghostty/kitty/wezterm doesn't hit
        # "unknown terminal type" in pagers.
        time.timeZone = "Asia/Jakarta";
        environment.enableAllTerminfo = true;
        i18n.defaultLocale = "en_US.UTF-8";
        i18n.extraLocaleSettings = {
          LC_ADDRESS = "id_ID.UTF-8";
          LC_IDENTIFICATION = "id_ID.UTF-8";
          LC_MEASUREMENT = "id_ID.UTF-8";
          LC_MONETARY = "id_ID.UTF-8";
          LC_NAME = "id_ID.UTF-8";
          LC_NUMERIC = "id_ID.UTF-8";
          LC_PAPER = "id_ID.UTF-8";
          LC_TELEPHONE = "id_ID.UTF-8";
          LC_TIME = "id_ID.UTF-8";
        };

        system.stateVersion = "25.11";
      };
  };

  # Host NAT for container egress — mirrors wireguard.nix's iptables pattern,
  # stays on iptables (no nftables flip). `ve-+` is the nspawn veth wildcard.
  networking.nat = {
    enable = true;
    externalInterface = externalInterface;
    internalInterfaces = [ "ve-+" ];
  };

  # Don't drop container traffic at the host firewall (mirrors tailscale0/wg0).
  networking.firewall.trustedInterfaces = [ "ve-+" ];

  # cgroup containment: nspawn containers run as root-level
  # `container@bareksa-box.service`, OUTSIDE user.slice — pin it into its own
  # slice so it doesn't compete unbounded against jellyfin/coding sessions.
  # CPUWeight=100 matches the coding tier (sessions.slice) per cpu-priority.md;
  # no hard MemoryMax (immich-style soft throttle only).
  systemd.slices.bareksa.sliceConfig = {
    CPUWeight = "100";
    MemoryHigh = "8G"; # TODO(tune): observe real VPN+podman peak via below/Grafana
  };

  # nixos-containers.nix already sets Slice = "machine.slice" — mkForce ours over it.
  systemd.services."container@bareksa-box".serviceConfig.Slice = lib.mkForce "bareksa.slice";

  # TODO(bareksa-box telemetry): nspawn forwards guest journald to the host
  # journal automatically; host Alloy already ships it to Loki. Confirm the
  # Alloy loki.source.journal config keeps container="bareksa-box" (or
  # _MACHINE_ID) as a low-cardinality label. Optional follow-up: a
  # bareksa_vpn_tunnel_up{provider} gauge once the user configures the VPN.
}
