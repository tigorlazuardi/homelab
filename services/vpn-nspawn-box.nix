# Shared systemd-nspawn NixOS container body for the "VPN box" pattern: office
# VPN (OpenVPN or Netbird) + Tailscale SSH ingress + nested rootless podman +
# herdr coding sessions. Structural twin factored out of bareksa-box.nix and
# strategix-box.nix — those two are now thin callers that pass only what
# differs (network addressing, slice name, and which office VPN). See
# plans/bareksa-box/SPEC.mdx for the full design + decisions.
#
# Pivoted from Incus: virtualisation.incus asserts networking.nftables.enable
# whenever the firewall is on, and this host's wireguard.nix uses raw iptables.
# systemd-nspawn (native NixOS `containers.*`) has no such requirement and keeps
# the host on iptables untouched.
#
# VPN credentials are NOT configured here (out of scope, user-manual):
#   sudo nixos-container root-login <name>   # or: sudo machinectl shell <name>
#   tailscale up                             # interactive auth, joins tailnet
#   # then SSH in over tailscale and configure netbird / openvpn manually.
{ lib, inputs }:
{
  name,
  hostAddress,
  localAddress,
  slice,
  officeVpn, # "openvpn" | "netbird"
  extraHosts ? "",
}:
assert lib.elem officeVpn [
  "openvpn"
  "netbird"
];
let
  # Same WAN interface wireguard.nix NATs through — reuse it so container
  # egress rides the existing iptables MASQUERADE path.
  externalInterface = "eth0";
in
{
  containers.${name} = {
    autoStart = true;

    # Fresh /24 per box, avoids wireguard's 10.0.0.0/24 and the tailnet's
    # 100.64.0.0/10.
    privateNetwork = true;
    inherit hostAddress localAddress;

    # /dev/net/tun for netbird/openvpn to create tunnel interfaces.
    enableTun = true;

    # VPN route setup inside the container's own netns.
    additionalCapabilities = [
      "CAP_NET_ADMIN"
      "CAP_NET_RAW"
    ];

    # /dev/fuse for envfs. services.envfs (enabled in the guest) provides
    # /usr/bin/env — the FHS shebang path npm/npx tools need (`#!/usr/bin/env
    # node`) — via a FUSE mount at /usr/bin. nspawn's minimal /dev has no
    # /dev/fuse, so that mount fails silently (fstab `nofail`) and /usr/bin/env
    # never appears (symptom: `/usr/bin/env: bad interpreter: No such file or
    # directory`). enableTun only wires /dev/net/tun; there is no enableFuse, so
    # bind the device in AND allow it on the container scope. nspawn keeps
    # CAP_SYS_ADMIN by default, so the guest can perform the fuse mount itself.
    allowedDevices = [
      {
        node = "/dev/fuse";
        modifier = "rwm";
      }
    ];
    bindMounts."/dev/fuse" = {
      hostPath = "/dev/fuse";
      isReadOnly = false;
    };

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
      lib.mkMerge [
        {
          # Own tailnet node — this is the SSH ingress path (bootstrap: root-login
          # once from the host, `tailscale up` interactively, then SSH over tailnet).
          services.tailscale.enable = true;

          services.openssh.enable = true;

          # sudo REQUIRES a password — defense-in-depth even though the box is
          # containerized and login is SSH-key-only. This repo is PUBLIC, so we do
          # NOT ship a password hash here; instead mutableUsers stays true and
          # tigor's password is set imperatively inside the box, once:
          #   sudo machinectl shell root@<name>   # then: passwd tigor
          # (root-in-container needs no password, so this always works to recover.)
          # A declarative sops hashedPasswordFile would need sops-nix wired into the
          # nspawn guest — overkill for a single-operator box.
          security.sudo.wheelNeedsPassword = true;
          users.mutableUsers = true;

          # netbird/openvpn = packages only, unconfigured (user supplies creds
          # manually). Coding env: claude-code + pi (llm-agents) + herdr binary,
          # with node/git/gh runtimes. Neovim binary via programs.neovim below.
          environment.systemPackages =
            lib.optionals (officeVpn == "openvpn") (
              with pkgs;
              [
                netbird
                openvpn
              ]
            )
            ++ (with pkgs; [
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
              gopls # Go language server (nixpkgs)
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
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKz9QiADKsexZdggCZpGuwBQp3yeZ4ulOVaTAQ5dx1tv tigor@windows"
              # homeserver host itself — lets this machine SSH/scp into the boxes
              # (e.g. copying config over from the homeserver user).
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH7Dd6s2s6iUrY2QRFDas2mhkG3ajjE2yP5J33foeKlJ homeserver@homeserver"
            ];
          };

          # Minimal — tailnet ingress (SSH) is the only expected inbound path.
          networking.firewall.enable = true;
          networking.firewall.allowedTCPPorts = [ 22 ];

          networking.extraHosts = extraHosts;

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
        }

        (
          if officeVpn == "netbird" then
            {
              # ── Keep tailscale WINNING over Netbird's full-tunnel ──────────────────
              # Netbird (advanced routing, the default on modern kernels) does NOT just
              # rewrite main's default like openvpn — it installs POLICY-ROUTING rules:
              #   prio 105:  from all lookup main suppress_prefixlength 0   (hide main default)
              #   prio 110:  not from all fwmark 0x1BD00 lookup 7120        (catch-all → netbird)
              # and puts the 0.0.0.0/0 exit-node default in its own table 7120 (dev wt0).
              # Rule 110 excludes ONLY netbird's own control mark (0x1BD00). Tailscale's
              # underlay is marked 0x80000 (≠ 0x1BD00) and tailnet-destined traffic is
              # unmarked — BOTH match netbird's catch-all at prio 110, which sits BELOW
              # (higher precedence than) tailscale's own rules (5210-5270). So without a
              # guard, netbird steals:
              #   (a) tailscale's control/DERP/encrypted-peer underlay → tailnet drops,
              #   (b) traffic TO the tailnet (100.64.0.0/10), incl. SSH reply packets →
              #       the box's ONLY ingress dies.
              #
              # Fix: TWO ip rules ABOVE netbird's 105 (numerically smaller = evaluated
              # first; ip rules are ordered by priority, not insertion, so this holds
              # regardless of who installs first):
              #   prio 100:  fwmark 0x80000 → clean-uplink table 52814 (real non-tunnel
              #              default) — tailscale underlay always egresses the clean path.
              #   prio 101:  to 100.64.0.0/10 → tailscale's own table 52 — tailnet peer
              #              traffic (incl. inbound-SSH replies) resolves via tailscale0
              #              before netbird's catch-all can grab it.
              # Both live outside tailscale's managed 5210-5270 range AND below netbird's
              # 105/110, and netbird only ever deletes its OWN rules — so neither VPN
              # touches ours. Every OTHER (unmarked, non-tailnet) app still rides the
              # full netbird tunnel as intended.
              #
              # PartOf tailscaled → re-applied whenever tailscale restarts (which
              # reinstalls its 52xx rules).
              systemd.services.tailscale-uplink-guard = {
                description = "Pin tailscale uplink + tailnet route outside Netbird full-tunnel (policy routing)";
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
                  # (gw + dev) so we never hardcode the guest iface name. Exclude tun/tap
                  # (openvpn-style) AND wt/nb (netbird, in case it runs LEGACY routing and
                  # writes its default into main via wt0). In netbird's default advanced
                  # mode the exit-node default lives in table 7120, not main, so main's
                  # default is already the clean host gateway — but the exclusion is cheap
                  # insurance. Retry briefly for the boot race where the default route
                  # isn't installed yet.
                  def=""
                  for _ in $(seq 1 10); do
                    def=$(ip route show default 2>/dev/null | grep -vE 'dev (tun|tap|wt|nb)[0-9]*' | head -1)
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
                  # Clean uplink table — independent of whatever netbird does to main.
                  ip route replace default via "$gw" dev "$dev" table "$tbl"
                  # (1) tailscale underlay (0x80000) → clean uplink, above netbird's 110.
                  ip rule del priority 100 2>/dev/null || true
                  ip rule add priority 100 fwmark 0x80000/0xff0000 table "$tbl"
                  # (2) tailnet-destined traffic → tailscale's table 52, above netbird's
                  # 110 catch-all. Table 52 holds tailscale's 100.64.0.0/10 → tailscale0
                  # route once tailscale is up; if it isn't, the lookup just falls through
                  # (no ingress anyway). Idempotent.
                  ip rule del priority 101 2>/dev/null || true
                  ip rule add priority 101 to 100.64.0.0/10 table 52
                  echo "tailscale-uplink-guard: fwmark 0x80000 -> table $tbl (default via $gw dev $dev); 100.64.0.0/10 -> table 52" >&2
                  # NOTE(validate-live): IPv6 tailnet (fd7a:115c:a1e0::/48) is NOT guarded
                  # here — ingress is tailscale-over-IPv4. If the box ever needs v6 tailnet
                  # reachability under netbird's v6 105/110 rules, mirror rule (2) with
                  # `ip -6 rule add priority 101 to fd7a:115c:a1e0::/48 table 52`.
                '';
                preStop = ''
                  ${pkgs.iproute2}/bin/ip rule del priority 100 2>/dev/null || true
                  ${pkgs.iproute2}/bin/ip rule del priority 101 2>/dev/null || true
                '';
              };

              # Office VPN = Netbird (full-tunnel). The daemon runs via the NixOS module;
              # first login is MANUAL (`netbird up --setup-key ...`, creds out of this
              # public repo). Unlike openvpn, netbird's client unit is a plain
              # Type=simple long-running daemon that comes up fast and does NOT block on
              # tunnel establishment — so it is SAFE in the boot transaction (no
              # Type=notify deadlock, no post-boot timer needed). Tunnel bring-up happens
              # asynchronously inside the already-started daemon; autoStart (default true)
              # makes it reconnect on reboot once configured.
              services.netbird.enable = true;

              # Order the netbird daemon AFTER the uplink guard so the guard's prio-100/101
              # rules exist before netbird installs its 105/110 rules. This is ordering
              # for tidiness only — NOT correctness: ip rules are evaluated by priority
              # number, not insertion order, so the guard wins regardless of who starts
              # first, and tailscale marks its underlay (0x80000) from socket creation so
              # there is no unmarked race window. Deliberately NO ExecStartPre wait on
              # tailscale: on a fresh (unauthenticated) box tailscale never reaches
              # Running, so such a wait would block netbird's start for its full timeout
              # INSIDE the boot transaction → the container never signals Ready → the host
              # start-times-out and restart-loops the whole box (observed 2026-07-13).
              # netbird's unit is Type=simple (forks fast, no notify gate), so left plain
              # it does not block boot. The module names the default client's unit
              # `netbird.service`.
              systemd.services.netbird = {
                after = [
                  "tailscaled.service"
                  "tailscale-uplink-guard.service"
                ];
                wants = [
                  "tailscaled.service"
                  "tailscale-uplink-guard.service"
                ];
              };
            }
          else
            {
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
              # container never signals "Ready" → the host `container@<name>`
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
            }
        )
      ];
  };

  # Host NAT for container egress — mirrors wireguard.nix's iptables pattern,
  # stays on iptables (no nftables flip). `ve-+` is the nspawn veth wildcard
  # (shared across all VPN boxes; every container's veth matches it).
  networking.nat = {
    enable = true;
    externalInterface = externalInterface;
    internalInterfaces = [ "ve-+" ];
  };

  # Don't drop container traffic at the host firewall (mirrors tailscale0/wg0).
  networking.firewall.trustedInterfaces = [ "ve-+" ];

  # cgroup containment: nspawn containers run as root-level
  # `container@<name>.service`, OUTSIDE user.slice — pin each into a child of the
  # shared `boxes.slice` (CPUQuota=400% total, in modules/cpu-budget.nix) so the
  # two office boxes together never exceed 4 threads and never starve
  # jellyfin/coding/media. Child = `boxes-${slice}.slice` (systemd dashed-naming =
  # parent/child); CPUWeight=100 splits the 400% between the boxes, MemoryHigh is
  # per-box (immich-style soft throttle only, no hard MemoryMax).
  systemd.slices."boxes-${slice}".sliceConfig = {
    CPUWeight = "100";
    MemoryHigh = "8G"; # TODO(tune): observe real VPN+podman peak via below/Grafana
  };

  # nixos-containers.nix already sets Slice = "machine.slice" — mkForce ours over it.
  systemd.services."container@${name}".serviceConfig.Slice = lib.mkForce "boxes-${slice}.slice";
}
