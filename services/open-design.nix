# Open Design bundled frontend is loopback-only; nginx preserves its API/SSE routing.
{ config, ... }:
{
  services.nginx.virtualHosts."open-design.tigor.web.id" = {
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:5174";
      proxyWebsockets = true;
      extraConfig = config.homelab.nginx.privateAllow;
    };
  };
}
