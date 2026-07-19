# Open Design bundled frontend is loopback-only; nginx preserves its API/SSE routing.
{ config, ... }:
{
  services.nginx.virtualHosts."open-design.tigor.web.id" = {
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:5174";
      proxyWebsockets = true;
      recommendedProxySettings = false;
      extraConfig = config.homelab.nginx.privateAllow + ''
        proxy_set_header Host 127.0.0.1:5174;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
      '';
    };
  };
}
