# JDownloader 2 (jlesage image) — download manager with a web/VNC UI.
#
# NOTE: jlesage images run an s6 init as root then drop to USER_ID. Under rootless
# we run it as root *inside the user namespace* (USER_ID/GROUP_ID=0), which maps to
# host `srv` (default rootless userns root→srv) → downloads land owned by srv.
# So this one does NOT use keep-id, and is intentionally LESS hardened than the
# others (s6 needs caps); revisit cap-drop/no-new-privileges at runtime cutover.
{
  home-manager.users.srv.virtualisation.quadlet.containers.jdownloader = {
    autoStart = true;
    containerConfig = {
      image = "docker.io/jlesage/jdownloader-2:latest";
      publishPorts = [ "127.0.0.1:5800:5800" ];
      volumes = [
        "/srv/data/state/jdownloader:/config"
        "/srv/data/downloads:/output"
      ];
      environments = {
        TZ = "Asia/Jakarta";
        USER_ID = "0"; # run as root inside userns → host srv
        GROUP_ID = "0";
      };
      autoUpdate = "registry";
    };
  };

  systemd.tmpfiles.rules = [
    "d /srv/data/state/jdownloader 0750 srv srv -"
  ];

  services.nginx.virtualHosts."jdownloader.tigor.web.id" = {
    forceSSL = true;
    # TODO(auth wave): re-add auth gate.
    locations."/" = {
      proxyPass = "http://127.0.0.1:5800";
      extraConfig = ''
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_connect_timeout 86400s;
      '';
    };
  };
}
