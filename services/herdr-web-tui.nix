# herdr-web-tui — private vhost for the herdr browser frontend. LAN + wireguard +
# tailscale + loopback only (homelab.nginx.privateAllow), no auth, no internet
# exposure — matches the SSH-only guard on the herdr daemon itself. WebSockets
# required (streams the herdr TUI over WS). Backend: modules/home/herdr-web-tui.nix
# on 127.0.0.1:8505.
{ config, ... }:
{
  services.nginx.virtualHosts."herdr.tigor.web.id" = {
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8505";
      proxyWebsockets = true;
      extraConfig = config.homelab.nginx.privateAllow;
    };
  };
}
