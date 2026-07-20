# strategix-box — systemd-nspawn NixOS container for the Strategix office VPN
# (Netbird full-tunnel), reachable over its own Tailscale node, with rootless
# podman nested inside. Structural twin of services/bareksa-box.nix; the ONE
# real difference is the office VPN: Netbird here instead of OpenVPN there. See
# plans/bareksa-box/SPEC.mdx for the shared design + decisions.
#
# Thin caller of services/vpn-nspawn-box.nix (shared VPN-box body); this box's
# only distinguishing traits are its addressing, slice name, office VPN
# (Netbird), and (currently empty) office /etc/hosts entries.
#
# VPN credentials are NOT configured here (out of scope, user-manual):
#   sudo nixos-container root-login strategix-box   # or: sudo machinectl shell strategix-box
#   tailscale up                                    # interactive auth, joins tailnet
#   netbird up --setup-key <KEY> [--management-url <URL>]   # joins Strategix netbird net
#   # (netbird stores its config; on reboot the daemon auto-reconnects.)
{ lib, inputs, ... }:
(import ./vpn-nspawn-box.nix { inherit lib inputs; }) {
  name = "strategix-box";

  # Fresh /24, distinct from bareksa-box's 10.100.0.0/24, wireguard's
  # 10.0.0.0/24 and the tailnet's 100.64.0.0/10.
  hostAddress = "10.101.0.1";
  localAddress = "10.101.0.2";

  slice = "strategix";
  uid = 1000;
  podmanSubIdStart = 493216;
  officeVpn = "netbird";

  # Strategix office-internal hostnames, reachable over the netbird VPN.
  # Fill in once the internal IPs are known — /etc/hosts wins over DNS, so
  # this forces internal IPs even when the pushed VPN DNS would return a
  # public address (same pattern as bareksa-box). Empty until provided.
  extraHosts = "";
}
# TODO(strategix-box telemetry): nspawn forwards guest journald to the host
# journal automatically; host Alloy already ships it to Loki. Confirm the
# Alloy loki.source.journal config keeps container="strategix-box" (or
# _MACHINE_ID) as a low-cardinality label. Optional follow-up: a
# strategix_vpn_tunnel_up{provider="netbird"} gauge once the VPN is configured.
