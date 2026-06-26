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
        # DoH only (TCP/443). DoQ (quic://, UDP/853) is intermittently dead on
        # this ISP — "no recent network activity" handshake timeouts — and with a
        # non-parallel mode a dead QUIC endpoint fails the query outright.
        upstream_dns = [
          "https://dns.adguard-dns.com/dns-query"
          "https://cloudflare-dns.com/dns-query"
        ];
        bootstrap_dns = [
          "94.140.14.14"
          "1.1.1.1"
        ];
        # parallel: race all upstreams, take the fastest — one slow/dead upstream
        # no longer stalls or fails the query (load_balance picked exactly one).
        upstream_mode = "parallel";
        cache_enabled = true;
        cache_size = 4194304;
        cache_optimistic = true;
        enable_dnssec = true;
        # Private reverse (PTR) resolution OFF: the system resolver (127.0.0.53)
        # forwards back to AdGuard (192.168.100.5 is resolved's uplink), so private
        # PTR lookups looped AdGuard→resolved→AdGuard until a 2s timeout — flooding
        # errors and stalling every LAN reverse lookup. No LAN reverse zone exists
        # anyway; answer NXDOMAIN locally and instantly.
        use_private_ptr_resolvers = false;
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
