# Suwayomi — manga server.
{
  homelab.containers.suwayomi = {
    image = "ghcr.io/suwayomi/suwayomi-server:stable";
    port = 4567;
    subdomain = "manga";
    networks = [ "arr" ];
    auth = true;
    uid = 1000;
    volumes = [
      "/var/mnt/state/suwayomi:/home/suwayomi/.local/share/Tachidesk"
      "/var/mnt/wolf/media/manga:/home/suwayomi/.local/share/Tachidesk/downloads"
    ];
    environments = {
      TZ = "Asia/Jakarta";
      AUTO_DOWNLOAD_CHAPTERS = "true";
      AUTO_DOWNLOAD_EXCLUDE_UNREAD = "false";
      MAX_SOURCES_IN_PARALLEL = "20";
      UPDATE_EXCLUDE_UNREAD = "false";
      UPDATE_EXCLUDE_STARTED = "false";
      FLARESOLVERR_ENABLED = "true";
      # reach flaresolverr by container name on the shared `arr` network.
      FLARESOLVERR_URL = "http://flaresolverr:8191";
    };
    tmpfiles = [
      # 0755 (o+x): under keep-id the container's root is a subuid, and crun must
      # traverse this dir to set up the nested `downloads` bind-mount below. The
      # stub must pre-exist so crun mounts onto it instead of mkdir-ing it (which
      # the subuid can't do in an srv-owned dir).
      "d /var/mnt/state/suwayomi 0755 srv srv -"
      "d /var/mnt/state/suwayomi/downloads 0755 srv media -"
      "d /var/mnt/wolf/media/manga 2775 srv media -"
    ];
  };
}
