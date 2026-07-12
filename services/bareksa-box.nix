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
        herdr = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;

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
        systemd.user.slices.sessions.Slice.CPUWeight = "100";
        systemd.user.services.herdr-server = {
          Unit.Description = "herdr server (terminal workspace daemon for coding sessions)";
          Install.WantedBy = [ "default.target" ];
          Service = {
            Type = "simple";
            WorkingDirectory = "%h";
            Environment = [
              "PATH=${herdrUserPath}"
              "TERM=xterm-256color"
              "COLORTERM=truecolor"
            ];
            ExecStart = "${herdr}/bin/herdr server";
            Slice = "sessions.slice";
            Restart = "always";
            RestartSec = 5;
          };
        };
        systemd.user.services.herdr-claude-retry = {
          Unit = {
            Description = "Auto-resume rate-limited claude panes in herdr";
            After = [ "herdr-server.service" ];
            Requires = [ "herdr-server.service" ];
            PartOf = [ "herdr-server.service" ];
          };
          Install.WantedBy = [ "default.target" ];
          Service = {
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
