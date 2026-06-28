---
name: run-as-srv
description: Use whenever emitting, recommending, or running ANY command as the srv user — `sudo -u srv`, `systemctl --user -M srv@.host` / `--machine=srv@.host`, `journalctl --user` for srv units, or `runuser -u srv`. ALWAYS prefix the command with `cd /tmp` (or another world-readable dir) first, because the human user's home is mode 0700 and srv (uid 1001) cannot chdir into it. Without it the command dies before its payload runs.
---

# Running commands as the `srv` user

All rootless app containers run under the non-login `srv` user (uid 1001). The
operator drives them from the `homeserver` login via `sudo -u srv …`. With the
NOPASSWD sudoers rule (`modules/users.nix`, `runAs = "srv"`), this needs no
password — but it still inherits the **caller's cwd**.

## The rule: `cd /tmp` first — every time

`sudo -u srv` keeps `homeserver`'s cwd. `/home/homeserver` is mode **0700**, so
srv (uid 1001) cannot `chdir` into it. The command dies **before the payload
runs**:

```
cannot chdir to /home/homeserver: Permission denied
```

This is silent-looking — it's not the podman/systemctl command failing, it's the
shell setup. Easy to misdiagnose. So **any** srv-user command — whether I run it
myself or hand it to the user to paste — MUST start from a world-readable dir.

```fish
cd /tmp
sudo -u srv XDG_RUNTIME_DIR=/run/user/1001 podman ps
```

Applies to every srv invocation form:

| form | needs `cd /tmp` first |
|---|---|
| `sudo -u srv XDG_RUNTIME_DIR=/run/user/1001 podman …` | yes |
| `sudo -u srv … systemctl --user …` | yes |
| `systemctl --user -M srv@.host …` / `--machine=srv@.host` | yes |
| `sudo -u srv … journalctl --user …` | yes |
| `runuser -u srv -- env XDG_RUNTIME_DIR=/run/user/1001 …` | yes |

## Build context too

A `podman build <context>` run as srv also fails if `<context>` lives under
`/home/homeserver`. Stage the build context in `/tmp` (world-readable), build
there, clean up. See `scripts/build-plan-image.sh`.

## Why a skill (not just the rule)

`.claude/rules/srv-podman.md` documents this same gotcha but is **path-scoped to
`*.nix` files**, so it does NOT load when recommending commands in plain
conversation — exactly when this gets forgotten. This skill triggers on the
*intent* of emitting a srv command, regardless of which files are open.
