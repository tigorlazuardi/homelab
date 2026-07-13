# below — process-per-slice + time-travel resource monitor for cgroup v2 hosts.
#
# Two services:
#   below-record  — daemon that samples cgroup/proc stats every 5s and writes
#                   to /var/log/below (enables `below replay` for time travel).
#   below-ttyd    — wraps `below live` in a pty via ttyd so it can be embedded
#                   as an iframe in the Grafana dashboard at tigor.web.id/below/.
#
# Capability-hardened (NOT root):
#   CAP_SYS_PTRACE     — read /proc/<pid>/mem, needed for per-process stats.
#   CAP_DAC_READ_SEARCH — read arbitrary cgroup/sys files regardless of ownership.
#
# TODO(cutover): verify below sees ALL slices (media-interactive/media-batch under
# user@1001, sessions under user@1000, system.slice). If caps insufficient, fall
# back to root (drop User=/Group=, remove AmbientCapabilities) and note here.
{ pkgs, ... }:
{
  users.users.below = {
    isSystemUser = true;
    group = "below";
    description = "below monitor daemon";
  };
  users.groups.below = { };

  environment.systemPackages = [ pkgs.below ];

  systemd.tmpfiles.rules = [
    "d /var/log/below 0750 below below -"
  ];

  # Record daemon — collects cgroup/proc samples every 5s.
  # Store dir defaults to /var/log/below (matches our tmpfiles + CAP_DAC_READ_SEARCH).
  # --store-size-limit 1073741824 = 1 GiB disk cap (bounds retention by size).
  # --disable-exitstats skips eBPF exitstats; our capability-hardened user has no BPF caps.
  systemd.services.below-record = {
    description = "below cgroup v2 data recorder";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.below}/bin/below record --store-size-limit 1073741824 --disable-exitstats";
      User = "below";
      Group = "below";
      AmbientCapabilities = [ "CAP_SYS_PTRACE" "CAP_DAC_READ_SEARCH" ];
      CapabilityBoundingSet = [ "CAP_SYS_PTRACE" "CAP_DAC_READ_SEARCH" ];
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # ttyd web terminal — serves `below live` as a browser-accessible TUI.
  # --base-path /below must match the nginx location prefix.
  # --writable is required: below live needs keyboard input (q to quit, arrows, etc.).
  systemd.services.below-ttyd = {
    description = "ttyd wrapper for below live (browser TUI)";
    wantedBy = [ "multi-user.target" ];
    after = [ "below-record.service" ];
    wants = [ "below-record.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.ttyd}/bin/ttyd --writable --base-path /below --interface 127.0.0.1 --port 7681 ${pkgs.below}/bin/below live";
      User = "below";
      Group = "below";
      AmbientCapabilities = [ "CAP_SYS_PTRACE" "CAP_DAC_READ_SEARCH" ];
      CapabilityBoundingSet = [ "CAP_SYS_PTRACE" "CAP_DAC_READ_SEARCH" ];
      Restart = "on-failure";
      RestartSec = "5s";
      # ttyd wraps `below live` in a pty; on stop the TUI child can ignore SIGTERM
      # and hang, stalling shutdown/`nixos-rebuild switch` toward the 90s default.
      # Cap hard at 3s — past that SIGKILL; a read-only monitor is safe to hard-kill.
      TimeoutStopSec = "3s";
    };
  };
}
