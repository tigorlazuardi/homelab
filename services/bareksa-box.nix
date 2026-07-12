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
{ lib, ... }:
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

    config =
      { pkgs, ... }:
      {
        # Own tailnet node — this is the SSH ingress path (bootstrap: root-login
        # once from the host, `tailscale up` interactively, then SSH over tailnet).
        services.tailscale.enable = true;

        services.openssh.enable = true;

        # Packages only — netbird/openvpn are left unconfigured; the user
        # supplies credentials manually after first entry ("terlalu sensitif").
        environment.systemPackages = with pkgs; [
          netbird
          openvpn
        ];

        # Nested rootless podman workloads, egress via whatever VPN owns the
        # box's default route. Nesting behavior (userns/cgroup delegation) is a
        # validate-live item per SPEC — defaults enabled here, revisit if
        # rootless podman refuses to start inside nspawn.
        virtualisation.podman = {
          enable = true;
          dockerCompat = true;
          defaultNetwork.settings.dns_enabled = true;
        };

        # SSH-ready login user mirroring the host operator (homeserver), same
        # authorized key set as modules/users.nix.
        users.users.homeserver = {
          isNormalUser = true;
          extraGroups = [ "wheel" ];
          shell = pkgs.bash;
          openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPO1aSG3/1vrgEPgK038tZ8+ipz3gZqr9hRT0JUteJXY tigor@fort"
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB/dGHD56+3qsLhUvmG4GeN8JrpYw7oGt0iQT+WkZzFu tigor@nexus"
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGUdNT+Pr015Li6Jp9cb1vCghd2C8EnecYwSC98qQCxl tigor@envy"
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
