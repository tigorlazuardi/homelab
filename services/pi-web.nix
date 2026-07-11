# pi-web — mobile web UI for the Pi Coding Agent. Private vhost: LAN + wireguard
# VPN + tailscale + loopback only, no internet exposure, no auth (user handles Pi
# login himself). WebSockets required (pi-web streams agent I/O over WS).
{ config, ... }:
{
  services.nginx.virtualHosts."pi.tigor.web.id" = {
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8504";
      proxyWebsockets = true;
      # privateAllow is a plain string (modules/quadlet-service.nix); bump the
      # upload cap alongside it for pi-web's default 64MB max image upload.
      extraConfig = config.homelab.nginx.privateAllow + "client_max_body_size 64m;\n";
    };
  };
}
