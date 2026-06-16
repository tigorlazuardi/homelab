# JDownloader 2 (jlesage image) — download manager with web/VNC UI.
#
# jlesage runs an s6 init as root then drops to USER_ID. Under rootless we run it
# as root *inside the user namespace* (USER_ID/GROUP_ID=0 → host srv via default
# rootless userns), so `userns = null` (no keep-id) and `harden = false`
# (s6 needs caps). Revisit hardening at runtime cutover.
{
  homelab.containers.jdownloader = {
    image = "docker.io/jlesage/jdownloader-2:latest";
    port = 5800;
    auth = true;
    userns = null;
    harden = false;
    volumes = [
      "/var/mnt/state/jdownloader:/config"
      "/var/mnt/nas/downloads:/output"
    ];
    environments = {
      TZ = "Asia/Jakarta";
      USER_ID = "0";
      GROUP_ID = "0";
    };
    tmpfiles = [ "d /var/mnt/state/jdownloader 0750 srv srv -" ];
    nginx.extraConfig = ''
      proxy_read_timeout 86400s;
      proxy_send_timeout 86400s;
      proxy_connect_timeout 86400s;
    '';
  };
}
