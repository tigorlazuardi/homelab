# Disk error-recovery — stop one bad HDD sector from hanging the whole host.
#
# Incident (2026-07-03): wolf (/dev/sda, Seagate IronWolf) hit uncorrectable
# sectors. On a bad read the drive retried ~30s while the kernel's 30s command
# timeout fired, looping ATA link resets. I/O to the disk stalled → dirty-page
# writeback throttle went host-wide → SSH/network starved → only a power-cycle
# recovered it (the NIC was healthy; the I/O cascade killed the management plane).
#
# Fix: SCT ERC (Error Recovery Control). NAS-class drives (Seagate IronWolf, WD Red)
# let us cap the drive's own read/write retry to 7.0s — BELOW the 30s kernel
# timeout. The drive then errors fast instead of hanging the bus; the kernel takes
# a clean I/O error and the host stays alive. Paired with vm.dirty_bytes in
# modules/memory-budget.nix (bounds how much stalled writeback can pile up).
#
# ERC is volatile: it resets on power-cycle AND on ATA link reset. A failing drive
# resets repeatedly, so a boot-only oneshot is not enough — a udev rule on
# add|change re-applies after every reset. Matched by serial (stable across sd*
# reordering). Replacing a drive → update its serial here.
{ pkgs, lib, ... }:
let
  setErc = "${pkgs.smartmontools}/bin/smartctl -l scterc,70,70"; # 70 = 7.0s (deciseconds)
  nasDriveSerials = [
    "WW659WEJ"     # wolf   — Seagate IronWolf ST4000VN006
    "WW68SEMC"     # fenrir — Seagate IronWolf ST4000VN006
    "WX12DC13F53S" # nas    — WD Red WD40EFZX
  ];
in
{
  services.udev.extraRules =
    lib.concatMapStringsSep "\n" (
      sn:
      ''ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd*[!0-9]", ENV{ID_SERIAL_SHORT}=="${sn}", RUN+="${setErc} /dev/%k"''
    ) nasDriveSerials
    + "\n";
}
