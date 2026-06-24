{
  # Hardware watchdog (/dev/watchdog0 present on this board). systemd pets it
  # every runtimeTime; if the host hangs hard — e.g. memory-pressure thrash that
  # freezes pid1 — petting stops and the hardware timer reboots the box. This
  # automates the manual power-cycle that was previously the only recovery.
  # rebootTime bounds a clean shutdown attempt before the hard reset.
  systemd.watchdog = {
    runtimeTime = "20s";
    rebootTime = "5min";
  };
}
