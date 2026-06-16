{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Per-vhost defaults: websockets on; use the wildcard ACME cert by default.
  options.services.nginx.virtualHosts = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.locations = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule { config.proxyWebsockets = lib.mkDefault true; }
          );
        };
        config.useACMEHost = lib.mkDefault "tigor.web.id";
      }
    );
  };

  config = {
    networking.firewall.allowedTCPPorts = [
      80
      443
    ];

    services.nginx = {
      enable = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;
      recommendedProxySettings = true;
      serverNamesHashBucketSize = 256;

      # Trust Cloudflare so $remote_addr is the real client IP.
      commonHttpConfig =
        let
          realIpsFromList = lib.concatMapStringsSep "\n" (x: "set_real_ip_from ${x};");
          fileToList = x: lib.splitString "\n" (builtins.readFile x);
          cfipv4 = fileToList (
            pkgs.fetchurl {
              url = "https://www.cloudflare.com/ips-v4";
              sha256 = "0ywy9sg7spafi3gm9q5wb59lbiq0swvf0q3iazl0maq1pj1nsb7h";
            }
          );
          cfipv6 = fileToList (
            pkgs.fetchurl {
              url = "https://www.cloudflare.com/ips-v6";
              sha256 = "1ad09hijignj6zlqvdjxv7rjj8567z357zfavv201b9vx3ikk7cy";
            }
          );
        in
        ''
          ${realIpsFromList cfipv4}
          ${realIpsFromList cfipv6}
          real_ip_header CF-Connecting-IP;
        '';
    };

    # HTTP-01 challenge endpoint + http→https redirect for the apex.
    services.nginx.appendHttpConfig = ''
      server {
        listen 0.0.0.0:80;
        listen [::0]:80;
        server_name tigor.web.id;
        location /.well-known/acme-challenge/ { root /var/lib/acme/acme-challenge; }
        location / { return 301 https://$host$request_uri; }
      }
    '';

    security.acme = {
      acceptTerms = true;
      defaults.email = "tigor.hutasuhut@gmail.com";
      defaults.dnsResolver = "192.168.100.5:53"; # AdGuard
      # One cert with every *.tigor.web.id vhost as a SAN (fewer LE calls).
      certs."tigor.web.id" = {
        webroot = "/var/lib/acme/acme-challenge";
        group = "nginx";
        extraDomainNames =
          let
            domains = lib.filterAttrs (
              name: value:
              (name != "tigor.web.id")
              && (value.forceSSL || value.onlySSL)
              && (value.useACMEHost == "tigor.web.id")
              && (lib.hasSuffix "tigor.web.id" name)
            ) config.services.nginx.virtualHosts;
          in
          lib.attrNames domains;
      };
    };
    users.users.nginx.extraGroups = [ "acme" ];
  };
}
