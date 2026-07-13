---
name: nixos-stale-runtime-reboot
description: Diagnose "stale running runtime" bugs on this NixOS homelab — weird failures that appear AFTER a `nix flake update` + `nixos-rebuild switch` where the running kernel or systemd/systemd-machined no longer matches the new system closure. Use whenever nspawn/container access breaks (`machinectl shell` → "Failed to get shell PTY", `nixos-container root-login` → "nsenter: reassociate to namespaces failed: No such process"), or any host runtime component misbehaves shortly after a flake update / switch, or the user mentions they updated the flake / bumped the kernel but did NOT reboot. Covers the booted-vs-current drift check and the reboot-vs-restart-machined decision.
---

# NixOS stale-running-runtime after flake update

## The class of bug

`nixos-rebuild switch` swaps the system closure and restarts *most* units, but it
does **not** reboot. Two things can keep running an OLD version after a switch:

1. **The kernel** — the running kernel is whatever booted; a switch that bumps the
   kernel does nothing until a **reboot**.
2. **Long-lived PID1-adjacent daemons** — `systemd` (PID 1) is only soft-reexec'd,
   and daemons like **`systemd-machined`** keep running their old binary unless
   explicitly restarted. When `nix flake update` bumps the `systemd` version, the
   host's `machinectl` / `nsenter` tooling is the NEW version but the running
   `systemd-machined` (and the container's PID1) may be the OLD one → **version
   skew**.

That skew is the classic cause of nspawn access breaking on THIS homelab
(bareksa-box / strategix-box), with symptoms identical across every container even
the healthy ones:

```
machinectl shell root@<box>        → Failed to get shell PTY: No such process
nixos-container root-login <box>   → nsenter: reassociate to namespaces failed: No such process
```

It looks like an nspawn bug or a dead container, but the container is `active` and
its `Leader` PID is alive — the host tooling just can't reassociate into its
namespaces because of the systemd version mismatch.

## Diagnose first (never guess — measure the drift)

```bash
# Kernel drift → reboot is the ONLY fix
echo "booted:  $(readlink /run/booted-system/kernel)"
echo "current: $(readlink /run/current-system/kernel)"

# Whole-closure drift (a switch happened since boot at all)
[ "$(readlink /run/booted-system)" = "$(readlink /run/current-system)" ] \
  && echo "IDENTICAL — nothing switched since boot" \
  || echo "DIFFER — switched since boot (only matters if kernel/systemd differ)"

# Is systemd-machined running the CURRENT systemd, or a stale one?
systemctl show systemd-machined -p ExecMainStartTimestamp \
  -p ExecStart --value | grep -oE '/nix/store/[^ ]*systemd[^ /]*'
# compare that store hash against:
readlink -f /run/current-system/systemd

# Is the container actually alive (rules out "dead container")?
machinectl show <box> -p Leader -p State     # State=running + a real Leader PID = alive
```

Interpretation:
- **booted kernel ≠ current kernel** → a new kernel is staged but not running →
  **reboot** to apply. Until then, kernel-coupled things (and sometimes nspawn) stay
  on the old kernel.
- **machined store-hash ≠ current systemd** → machined is stale → the nspawn access
  skew. Fix without a full reboot: `sudo systemctl restart systemd-machined`
  (containers keep running; only the management daemon restarts). A reboot also
  fixes it.
- **booted == current (kernel + systemd)** → no drift; the skew is already resolved
  (e.g. machined got restarted by a later switch). Look elsewhere for the bug.

## The rule — suggest a reboot after a kernel/systemd-bumping flake update

When the user reports a post-`flake update` bug on this host, or says they updated
the flake / bumped the kernel and have **not rebooted**:

1. Run the drift check above.
2. If **kernel drifted** → recommend `sudo reboot` (only a reboot loads a new
   kernel). State plainly that a `switch` alone cannot apply it.
3. If only **systemd/machined drifted** (nspawn access symptom) → offer the cheap
   fix first: `sudo systemctl restart systemd-machined`; a reboot is the definitive
   clean-slate alternative.
4. If **no drift** → do NOT hand-wave "just reboot"; the cause is something else,
   keep debugging.

A reboot is the honest fix for kernel drift and a guaranteed clean slate for any
running-runtime skew — recommend it deliberately, backed by the drift check, not as
a reflex.

## Worked precedent (2026-07-13)

strategix-box + bareksa-box both returned "No such process" on `root-login`. Two
independent causes were untangled: (a) strategix was genuinely restart-looping on a
bad guest config (fixed in nix), and (b) BOTH boxes' shell access failed due to a
`systemd-machined` skew from an earlier flake-update+switch without a restart —
cleared once machined was restarted by a later switch. Kernel was NOT drifted at the
time, so a reboot was optional; the machined restart was the operative fix.
