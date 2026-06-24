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
    # AdGuard (.5) is primary so the host benefits from local ad-blocking and
    # split-horizon names. 1.1.1.1 is a fallback ONLY for the host's own
    # resolution: when AdGuard is down the box can still resolve outbound instead
    # of going fully blind. LAN clients still point at AdGuard, so their filtering
    # is unaffected.
    nameservers = [
      "192.168.100.5"
      "1.1.1.1"
    ];
  };

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
