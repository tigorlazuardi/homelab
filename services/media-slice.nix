# CPU sub-slices for ALL media services running under the srv user.
# Both live inside user-1001.slice which gets 60% of the global user.slice budget
# (see modules/cpu-budget.nix).
#
# media-interactive.slice (CPUWeight=200): jellyfin.
#   Live playback transcodes are latency-sensitive. High weight ensures jellyfin wins
#   over batch jobs and (combined with user-1001's 60% share) wins over coding sessions.
#   No CPUQuota: transcode is spiky, not sustained — thermal risk is low.
#
# media-batch.slice (CPUWeight=10, CPUQuota=240%): ytptube + immich (all containers).
#   Batch downloads and photo import run sustained → hard quota prevents thermal
#   issues (immich ffmpeg pegs all cores → 98°C without a ceiling). 240% = 3 threads
#   max. CPUWeight yields to jellyfin and coding sessions when competing.
#
# Add a service:
#   interactive UI/playback → serviceConfig.Slice = "media-interactive.slice"
#   batch import/download   → serviceConfig.Slice = "media-batch.slice"
{
  home-manager.users.srv.systemd.user.slices = {
    media-interactive.Slice = {
      CPUWeight = "200"; # interactive playback wins within srv session
    };
    media-batch.Slice = {
      CPUQuota = "240%"; # 3 threads max — immich sustained ffmpeg caused 98°C without this
      CPUWeight = "10";  # batch yields to jellyfin and coding sessions
    };
  };
}
