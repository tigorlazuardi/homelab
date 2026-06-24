# System-level memory resilience — the memory analogue of cpu-budget.nix.
# A memory-pressure spike previously thrashed the whole host (swap on NVMe) until
# SSH/network became unreachable and only a power-cycle recovered it. These knobs
# (a) make the kernel reclaim before swapping hard, (b) let systemd-oomd kill the
# worst cgroup on swap exhaustion as a global backstop (per-slice pressure kill is
# set on media-batch in services/media-slice.nix), and (c) reserve a memory floor
# for the management plane so SSH stays reachable under pressure.
{
  boot.kernel.sysctl."vm.swappiness" = 10;

  systemd.oomd = {
    enable = true;
    enableRootSlice = true; # swap-exhaustion backstop across all cgroups
  };

  # Protect the management plane: guarantee a small memory floor so these survive
  # global pressure and we can still SSH in to intervene (instead of power-cycling).
  systemd.services.sshd.serviceConfig.MemoryMin = "32M";
  systemd.services.systemd-networkd.serviceConfig.MemoryMin = "16M";
}
