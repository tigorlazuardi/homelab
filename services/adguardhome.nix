# AdGuard Home — DNS server (native service). Also the host's DNS resolver and
# the source of *.tigor.web.id rewrites pointing at this box.
{ ... }:
let
  serverIP = "192.168.100.5";
in
{
  services.adguardhome = {
    enable = true;
    mutableSettings = true; # seed once; UI edits persist
    # Web UI on the module default 0.0.0.0:3000.
    settings = {
      dns = {
        bind_hosts = [
          "192.168.100.5"
          "10.0.0.1" # wireguard gateway
        ];
        port = 53;
        upstream_dns = [
          "quic://dns.adguard-dns.com"
          "https://dns.adguard-dns.com/dns-query"
          "quic://cloudflare-dns.com"
          "https://cloudflare-dns.com/dns-query"
        ];
        bootstrap_dns = [
          "94.140.14.14"
          "1.1.1.1"
        ];
        upstream_mode = "load_balance";
        cache_enabled = true;
        cache_size = 4194304;
        cache_optimistic = true;
        enable_dnssec = true;
        use_private_ptr_resolvers = true;
      };
      tls.enabled = false;
      filters = [
        {
          enabled = true;
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
          name = "AdGuard DNS filter";
          id = 1;
        }
        {
          enabled = true;
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt";
          name = "AdAway Default Blocklist";
          id = 2;
        }
      ];
      filtering = {
        filtering_enabled = true;
        rewrites_enabled = true;
        protection_enabled = true;
        rewrites = [
          {
            domain = "tigor.web.id";
            answer = serverIP;
            enabled = true;
          }
          {
            domain = "*.tigor.web.id";
            answer = serverIP;
            enabled = true;
          }
        ];
      };
    };
  };

  networking.firewall = {
    allowedTCPPorts = [
      53
      3000 # web UI — LAN only (router blocks external)
    ];
    allowedUDPPorts = [ 53 ];
  };

  # Public UI behind tinyauth forward-auth. AdGuard binds its LAN address (not
  # loopback), so proxy there. Set an AdGuard user/password too — defence in depth.
  services.nginx.virtualHosts."adguard.tigor.web.id" = {
    forceSSL = true;
    tinyauth.enable = true;
    locations."/".proxyPass = "http://${serverIP}:3000";
  };
}
