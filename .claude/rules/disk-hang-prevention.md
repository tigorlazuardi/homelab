---
paths:
  - "modules/disk-error-recovery.nix"
  - "modules/memory-budget.nix"
  - "services/smartd.nix"
  - "hardware/kernel.nix"
---

# Disk-hang prevention (dying HDD must not freeze the whole host)

A single failing HDD with unreadable sectors can take down the **entire host** —
SSH and network included — forcing a physical power-cycle. Root cause and the
standing mitigations are below. Incident: 2026-07-03, nas (WD40EFZX).

## The failure chain

1. A read lands on an **uncorrectable (UNC) sector**. `dmesg`: `ata<N>.00: error:
   { UNC }` + `Unrecovered read error - auto reallocate failed`.
2. By default the drive retries the bad read for **~30 s** while the kernel's
   default SCSI command timeout is also ~30 s → they collide → the kernel resets
   the ATA link and **retries in a loop**. I/O to that disk stalls.
3. Stalled writeback = dirty pages that can't flush. Once dirty pages cross the
   **global** `dirty_ratio` threshold, the kernel throttles **all** writes
   host-wide (even to the healthy NVMe) → journald/sshd/networkd block on write.
4. Reclaim can't free the stuck writeback pages → memory pressure → swap thrash →
   management plane dies → **only a power-cycle recovers**. The NIC is fine; the
   I/O cascade is what kills networking.

## The standing fixes (already in the config)

- **`modules/disk-error-recovery.nix`** — a udev rule sets **SCT ERC = 7.0 s**
  (`smartctl -l scterc,70,70`) on each NAS-class HDD, on `add|change` (re-applies
  after every link reset, since ERC is volatile). 7 s < the 30 s kernel timeout →
  the drive **errors fast**, the kernel takes a clean I/O error, no reset storm,
  host stays alive. Verify: `cmd_age` in the dmesg error drops from ~30s to ~4s.
- **`modules/memory-budget.nix`** — `vm.dirty_bytes=256MiB` +
  `vm.dirty_background_bytes=64MiB` (absolute, replacing the %-based default of
  ~3 GB on 16 GB RAM). Bounds how much stalled writeback can pile up before the
  throttle, so a stuck disk can't fill RAM with un-flushable dirty pages.

Both are necessary: scterc stops the reset storm, dirty caps stop the writeback
avalanche. Neither *cures* the disk — they keep the host up while it's dying.

## Gotcha: `sd*` letters reorder across boots — diagnose by port + serial

`/dev/sda|sdb|sdc` are assigned in probe order and **change between boots**. In the
2026-07-03 incident the console photo showed `dev sda` but the real culprit was
`sdc` — same physical disk, different letter. The **stable** identifiers:

- **`ata<N>` port** (e.g. `ata6`) — fixed to a physical SATA port across boots.
- **serial / `/dev/disk/by-id/ata-<model>_<serial>`** — fixed to the drive.

When diagnosing: `dmesg | grep 'ata<N>'` for the port, `lsblk -o NAME,SERIAL,MODEL`
+ `ls -l /dev/disk/by-id` to map letter→serial, `smartctl -a /dev/disk/by-id/...`.
Never trust the `sd*` letter from a previous boot.

## Adding / replacing an HDD

- Add the drive's **serial** to `nasDriveSerials` in
  `modules/disk-error-recovery.nix`. Confirm it supports ERC first:
  `smartctl -l scterc /dev/sdX` must not say "not supported" (WD Red / Seagate
  IronWolf do; cheap desktop drives — WD Blue/Green, Barracuda — often do NOT).
- **Non-ERC drive**: you can't cap retries at the drive. Fall back to raising the
  kernel per-device timeout instead (`echo 180 > /sys/block/sdX/device/timeout`
  via a udev rule) so the kernel waits out the drive instead of reset-looping.

## Reclaiming a pending sector

`Current_Pending_Sector` counts sectors that failed a read and are queued for
remap. The drive **cannot auto-reallocate on read** ("auto reallocate failed") —
only a **write** to that LBA triggers the remap. So a pending sector keeps throwing
UNC on every read until the file occupying it is **overwritten or deleted** (freeing
the block for reuse). Find the file: `debugfs -R "icheck <fs-block>" /dev/sdX1`
then `ncheck <inode>`. For a disposable disk, deleting the offending file is the
cheapest way to stop a recurring boot-time reader from re-tripping the sector.
