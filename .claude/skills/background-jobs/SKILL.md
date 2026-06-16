---
name: background-jobs
description: Use when starting a long-running shell task (rsync, large copies, backups, restores, builds, downloads) that must outlive the agent turn/session and be pollable later — run it as a named systemd-run --user transient unit instead of nohup/&, so the host's user manager owns it and status survives across sessions and context compaction.
---

# Long-running background jobs (systemd-run --user)

For any task that runs longer than a couple of minutes — `rsync`, bulk copies,
backups, restores, big downloads — **do not** use `nohup cmd &` or a raw `&`.
Those are tied to the shell, not pollable as a unit, give no structured exit
status, and are awkward to track across a new session or after context
compaction.

Run it as a **named transient systemd user unit** instead. The host's `--user`
systemd manager owns the process, so it keeps running when the agent turn ends,
and any later session can poll its state, exit code, and output by unit name.

## Prerequisites (verify once)

```bash
loginctl show-user "$USER" -p Linger      # must be Linger=yes (else: loginctl enable-linger $USER)
systemctl --user is-system-running        # user manager must be up (running/degraded ok)
```

On this homeserver `homeserver` already has `Linger=yes`.

## Start a job

```bash
systemd-run --user \
  --unit=<job-name> \
  --description="<what it does>" \
  --property=RemainAfterExit=yes \
  -- <command> [args...]
```

- `--unit=<job-name>` — stable, descriptive name (e.g. `cutover-rsync-arr`). This
  is the handle every later poll uses; pick something a future session will
  recognise.
- `--property=RemainAfterExit=yes` — **the key flag**. After the command finishes
  the unit stays `active (exited)` instead of being garbage-collected, so its
  result is still pollable cross-session. Do NOT pass `--collect` (that auto-GCs
  on exit and defeats the point).
- Output (stdout+stderr) is captured to the journal automatically — no manual log
  redirection needed. For tools with carriage-return progress bars (`rsync
  --info=progress2`), also tee to a logfile if you want a clean tail (see below).

Example (the cutover media copy):

```bash
systemd-run --user --unit=cutover-rsync-arr \
  --description="rsync arr media+torrents nas->wolf (hardlinks)" \
  --property=RemainAfterExit=yes \
  -- rsync -rlptDH --info=progress2,stats2 --no-inc-recursive \
     /var/mnt/nas/mediaserver/servarr/data/ /var/mnt/wolf/_arrstage/
```

## Poll it (any later session)

```bash
# one-line state
systemctl --user show -p ActiveState,SubState,ExecMainStatus,ExecMainCode <job-name>
```

Interpret:

| ActiveState | SubState | meaning |
|---|---|---|
| `active` | `running` | still working |
| `active` | `exited` | **finished OK** (check `ExecMainStatus=0`) |
| `failed` | `failed` | **finished with error** (`ExecMainStatus` = exit code) |

`ExecMainStatus` is the process exit code (0 = success). `ExecMainCode=1` just
means "exited normally" (CLD_EXITED) — read `ExecMainStatus` for the real result.

```bash
systemctl --user status <job-name> --no-pager        # human summary + recent log
journalctl --user -u <job-name> -n 30 --no-pager     # last 30 log lines
journalctl --user -u <job-name> -f                   # live follow
```

## Progress for rsync-style tools

The journal keeps full lines but `--info=progress2` emits `\r`-updated lines.
For a clean single-line progress read, also tee to a file:

```bash
systemd-run --user --unit=<job> --property=RemainAfterExit=yes \
  -- bash -c 'rsync -rlptDH --info=progress2 SRC/ DST/ > /path/job.log 2>&1'
# then:
tail -c 200 /path/job.log | tr '\r' '\n' | tail -1
```

## Clean up (only when you no longer need the result)

```bash
systemctl --user stop <job-name>          # transient unit → removed entirely
systemctl --user reset-failed <job-name>  # if it ended failed, clears it
```

Leave the unit in place while the result still matters — that is the whole point
(poll it next session). Only stop/reset once you've consumed the outcome.

## Root-owned work

`--user` runs as the calling user (no root). If the job genuinely needs root
(rare — most data here is readable as `homeserver`), use the system manager and
keep the same flags:

```bash
sudo systemd-run --unit=<job-name> --property=RemainAfterExit=yes -- <command>
# poll without --user: systemctl status / journalctl -u <job-name>
```

Prefer `--user` whenever the files are readable/writable as the normal user —
it needs no password and matches how the rootless services run.

## Why not `nohup cmd &`

- Dies with the controlling shell in some setups; not reliably cross-session.
- No unit name → polling is PID-guessing that breaks across sessions/reboots.
- No structured exit status; you parse logs to guess success.
- No journal integration.

`systemd-run --user` fixes all four: stable name, host-owned, structured status,
journald logs — pollable from a fresh session or after compaction.
