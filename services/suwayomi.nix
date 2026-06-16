# Suwayomi — manga server.
{
  homelab.containers.suwayomi = {
    image = "ghcr.io/suwayomi/suwayomi-server:stable";
    port = 4567;
    subdomain = "manga";
    auth = true;
    uid = 1000;
    volumes = [
      "/srv/data/state/suwayomi:/home/suwayomi/.local/share/Tachidesk"
      "/srv/data/media/manga:/home/suwayomi/.local/share/Tachidesk/downloads"
    ];
    environments = {
      TZ = "Asia/Jakarta";
      AUTO_DOWNLOAD_CHAPTERS = "true";
      AUTO_DOWNLOAD_EXCLUDE_UNREAD = "false";
      MAX_SOURCES_IN_PARALLEL = "20";
      UPDATE_EXCLUDE_UNREAD = "false";
      UPDATE_EXCLUDE_STARTED = "false";
      FLARESOLVERR_ENABLED = "true";
      # rootless: reach flaresolverr's host-published port.
      FLARESOLVERR_URL = "http://host.containers.internal:8191";
    };
    tmpfiles = [
      "d /srv/data/state/suwayomi 0750 srv srv -"
      "d /srv/data/media/manga 2775 srv media -"
    ];
  };
}
