# webhook — native NixOS service (not a container). Runs as root so deploy hooks
# can restart services. Enabled only when something defines a hook (e.g. wallrus).
#
# CAUTION: hook scripts run with full root access.
{ config, lib, ... }:
{
  config = lib.mkIf (config.services.webhook.hooks != { }) {
    sops.secrets."webhook/basic_auth" = {
      sopsFile = ../secrets/webhook.yaml;
      key = "basic_auth";
      owner = "nginx";
      group = "nginx";
    };

    services.webhook = {
      enable = true;
      user = "root";
      group = "root";
    };

    services.nginx.virtualHosts."webhook.tigor.web.id" = {
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:9000";
        basicAuthFile = config.sops.secrets."webhook/basic_auth".path;
      };
    };
  };
}
