# Shared CPU budget for ALL media-processing services (immich, jellyfin, ...).
# One parent slice with a single ceiling = 40% of the 8-thread host (320%).
# Members carry NO individual quota — only weights — so the budget floats: if
# jellyfin is idle, immich's import can use the full 40%, and vice-versa. When
# both want CPU, CPUWeight decides the split (jellyfin's interactive transcodes
# beat immich's batch import). The whole group's low CPUWeight also makes media
# lose to default-weight (100) system/interactive units, keeping the host
# responsive under load.
#
# Add a service to the budget by setting `serviceConfig.Slice = "media.slice"`
# (helper services) or `serviceConfig.Slice` on the quadlet container.
{
  home-manager.users.srv.systemd.user.slices.media.Slice = {
    CPUQuota = "320%"; # 40% of 8 threads — the total media-processing ceiling
    CPUWeight = "30"; # whole media group yields to system/interactive work
  };
}
