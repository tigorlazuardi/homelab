# Tailscale VPN (native edge, alongside wireguard which is kept as an independent
# self-hosted fallback path). This node is a SUBNET ROUTER (advertises the LAN so
# tailnet clients reach 192.168.100.0/24 over tailscale — the *.tigor.web.id vhosts
# work unchanged via the existing AdGuard rewrite -> 192.168.100.5) and an EXIT NODE
# (one-tap full-tunnel from the mobile app). Private vhosts opt tailnet clients in
# additively with `allow 100.64.0.0/10;` (the CGNAT source range) in their allow-list.
#
# --accept-dns=false: don't let tailscale rewrite the host resolver (AdGuard owns
# it). For client-side ad-blocking over the exit node, set the tailnet global
# nameserver to 192.168.100.5 in the admin console (reachable via the subnet route).
#
# Runtime (admin console, after first `up`): approve the advertised route + exit
# node (or pre-approve via ACL autoApprovers on the auth key's tag).
{ config, lib, ... }:
{
  sops.secrets."tailscale/authkey".sopsFile = ../secrets/tailscale.yaml;

  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets."tailscale/authkey".path;
    useRoutingFeatures = "server"; # ip_forward + rp_filter for subnet router / exit node
    extraUpFlags = [
      "--advertise-routes=192.168.100.0/24"
      "--advertise-exit-node"
      "--accept-dns=false"
    ];
    openFirewall = true; # UDP 41641 for direct connections
  };

  # Trust the tailscale interface (mirrors wg0) so tailnet + subnet-routed traffic
  # isn't dropped by the host firewall.
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
}
