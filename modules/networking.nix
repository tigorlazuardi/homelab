{
  networking = {
    hostName = "homeserver";
    enableIPv6 = false;
    # Single NIC, so no need for predictable names; interface stays "eth0".
    usePredictableInterfaceNames = false;
    # Static box: no DHCP. DHCP only added a failure mode here — eth0 used to
    # carry both a DHCP lease AND the static .5 (set in adguardhome.nix), and the
    # default route rode the DHCP src. A lease renewal/flap dropped outbound
    # connectivity while services bound to .5 lingered. See systemd.network below.
    useDHCP = false;
    # AdGuard (.5) is the host's ONLY resolver, so host- and container-originated
    # lookups get local ad-blocking + split-horizon names and leave via AdGuard's
    # DoH (never plain to a third party). 1.1.1.1/8.8.8.8 live in resolved's
    # fallbackDns instead — a TRUE last-resort resolved uses ONLY when AdGuard is
    # fully unreachable (e.g. before it starts at boot). Listing them in
    # `nameservers` made resolved treat them as co-equal DNS= servers and stick to
    # 1.1.1.1 after any failover, silently bypassing AdGuard.
    nameservers = [ "192.168.100.5" ];
  };

  services.resolved.settings.Resolve.FallbackDNS = [
    "1.1.1.1"
    "8.8.8.8"
  ];

  # Static networking via systemd-networkd.
  systemd.network = {
    enable = true;
    networks."10-eth0" = {
      matchConfig.Name = "eth0";
      address = [ "192.168.100.5/24" ];
      routes = [ { Gateway = "192.168.100.1"; } ];
      networkConfig.DNS = "192.168.100.5";
      linkConfig.RequiredForOnline = "routable";
    };
  };
}
