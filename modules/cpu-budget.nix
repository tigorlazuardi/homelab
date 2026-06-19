# System-level CPU budget: hard ceiling for ALL user processes (homeserver + srv).
# Sets user.slice quota and weights so the kernel enforces the right priority order
# without per-service quotas throughout the codebase.
#
# Priority tier (high → low, effective weight through cgroup v2 hierarchy):
#   1. jellyfin     (media-interactive.slice under user-1001) ≈ 57% of user.slice
#   2. coding       (sessions.slice under user-1000)          ≈ 40% of user.slice
#   3. batch media  (media-batch.slice under user-1001)       ≈  3% of user.slice
#
# See services/media-slice.nix (srv user slices) and modules/home/claude-sessions.nix
# (homeserver sessions.slice) for the per-user sub-slices.
{
  # Global ceiling: 85% of 8 threads = 680%. All user services combined (homeserver +
  # srv) may not exceed this — leaves 15% headroom for system + kernel work.
  systemd.slices.user.sliceConfig.CPUQuota = "680%";

  # srv (uid 1001): runs media containers. Higher weight → gets 60% of user.slice
  # budget when competing with homeserver. Lets jellyfin (within media-interactive.slice)
  # beat coding sessions despite sitting in a different cgroup subtree.
  systemd.slices."user-1001".sliceConfig.CPUWeight = "150";

  # homeserver (uid 1000): runs zellij+claude sessions. 40% of user.slice.
  # Beats batch media (ytptube, immich) because those sit in media-batch.slice
  # with CPUWeight=10 within srv's session — very low effective share.
  systemd.slices."user-1000".sliceConfig.CPUWeight = "100";
}
