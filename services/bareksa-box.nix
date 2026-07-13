# bareksa-box — systemd-nspawn NixOS container for the office VPN (netbird +
# OpenVPN), reachable over its own Tailscale node, with rootless podman nested
# inside. See plans/bareksa-box/SPEC.mdx for the full design + decisions.
#
# Thin caller of services/vpn-nspawn-box.nix (shared VPN-box body); this box's
# only distinguishing traits are its addressing, slice name, office VPN
# (OpenVPN), and office /etc/hosts entries.
{ lib, inputs, ... }:
(import ./vpn-nspawn-box.nix { inherit lib inputs; }) {
  name = "bareksa-box";

  # Fresh /24, avoids wireguard's 10.0.0.0/24 and the tailnet's 100.64.0.0/10.
  hostAddress = "10.100.0.1";
  localAddress = "10.100.0.2";

  slice = "bareksa";
  officeVpn = "openvpn";

  # Office-internal hostnames, reachable over the office VPN (full-tunnel).
  # Mirrors ~/dotfiles nixos/environments/bareksa/system/networking.nix.
  # /etc/hosts wins over DNS, so gitlab.bareksa.com forces the internal IP
  # even when the pushed VPN DNS would return a public Cloudflare address.
  extraHosts = ''
    192.168.50.217 gitlab.bareksa.com
    192.168.3.50 kafka.dev.bareksa.local
    192.168.50.102 kafka-host-1 kafka-cluster-jkt-1
    192.168.50.103 kafka-host-2 kafka-cluster-jkt-2
    192.168.50.104 kafka-host-3 kafka-cluster-jkt-3
    10.138.192.35 redis-stock.dev.bareksa.local
    192.168.50.202 kafka-console.prod.bareksa.local
  '';
}
# TODO(bareksa-box telemetry): nspawn forwards guest journald to the host
# journal automatically; host Alloy already ships it to Loki. Confirm the
# Alloy loki.source.journal config keeps container="bareksa-box" (or
# _MACHINE_ID) as a low-cardinality label. Optional follow-up: a
# bareksa_vpn_tunnel_up{provider} gauge once the user configures the VPN.
