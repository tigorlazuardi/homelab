# Host housekeeping: keep the SSD healthy and the journal bounded so disk
# pressure never becomes a failure mode on its own.
{
  # Periodic TRIM for the NVMe (state + swap live there).
  services.fstrim.enable = true;

  # Cap the systemd journal so logs can't slowly fill the root filesystem.
  services.journald.extraConfig = ''
    SystemMaxUse=2G
    SystemKeepFree=1G
  '';
}
