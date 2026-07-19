# Open Design user daemon + bundled frontend. Both bind loopback; nginx owns ingress.
{ inputs, ... }:
{
  imports = [ inputs.open-design.homeManagerModules.default ];

  services.open-design = {
    enable = true;
    autoStart = true;
    extraEnv.OD_BIND_HOST = "127.0.0.1";
    webFrontend = {
      enable = true;
      host = "127.0.0.1";
      allowedOrigins = [ "https://open-design.tigor.web.id" ];
    };
  };
}
