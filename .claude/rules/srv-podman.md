---
description: Gotchas when running podman/systemctl as the srv user and writing image names.
paths:
  - "services/**.nix"
  - "containers/**"
  - "scripts/**"
  - "modules/quadlet-service.nix"
---

# Running podman as srv + image naming

## cwd gotcha: `cd` out of homeserver's home before `sudo -u srv`

`sudo -u srv ...` keeps the **caller's cwd**. The human user `homeserver`'s home
(`/home/homeserver`) is `0700` — `srv` (uid 1001) can't `chdir` into it, so the
command dies before the payload even runs:

```
cannot chdir to /home/homeserver: Permission denied
```

**Always `cd` to a world-readable dir first** (`/tmp` is the convention):

```fish
cd /tmp
sudo -u srv XDG_RUNTIME_DIR=/run/user/1001 podman ...
```

Same for `systemctl --user -M srv@` / `journalctl --user`. In scripts: `cd "$dir"`
before the `sudo -u srv` line (see `scripts/build-plan-image.sh`).

## Build context can't live under /home/homeserver

A `podman build <context>` run as `srv` also fails if `<context>` is under
`/home/homeserver` (srv can't read it). **Stage the build context in `/tmp`**
(world-readable), build from there, clean up. `scripts/build-plan-image.sh` does
this: `mktemp -d /tmp/...`, copy the `Containerfile` in, `cd` in, build, `rm -rf`.

## Image names MUST be fully qualified

Rootless podman here has **no unqualified-search registry default**, so a short
name like `node:22-bookworm` triggers an interactive "docker.io or quay.io?"
prompt — which **blocks/fails any non-interactive build or pull** (Dockerfile
`FROM`, quadlet `Image=`, `podman build`).

Always write the **full registry path**:

| short (BAD) | fully qualified (GOOD) |
|---|---|
| `node:22-bookworm` | `docker.io/library/node:22-bookworm` |
| `owner/app:tag` | `docker.io/owner/app:tag` or `ghcr.io/owner/app:tag` |
| `app:tag` (quay) | `quay.io/owner/app:tag` |

- Docker Hub **official** images live under `library/` → `docker.io/library/<name>`.
- Locally-built images use the `localhost/` registry: `localhost/plan:latest`.
- Applies to `Containerfile` `FROM` lines AND `homelab.containers.<name>.image`.
