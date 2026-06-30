---
name: inspect-container-image
description: Use BEFORE adding/pinning any rootless container service to this homelab (homelab.containers.<name> / quadlet) or whenever you need a container image's digest, exposed port, run-as uid, or entrypoint behavior without pulling it. Inspect the image remotely with skopeo run ephemerally via comma (`,`). Notably skopeo here fails with "registries.conf must be in v2 format but is in v1" — work around it with a throwaway v2 conf via CONTAINERS_REGISTRIES_CONF.
---

# Inspect a container image before wiring it into nix

Resolve the facts that drive the helper knobs (`image`, `port`, `uid`, `harden`,
digest pin) from the image itself — don't guess. Done remotely, no pull, no install.

## The gotcha (always hits)

`, skopeo inspect docker://...` dies:

```
Error parsing image name ...: registries.conf must be in v2 format but is in v1
```

Host `/etc/containers/registries.conf` is v1; skopeo 1.23 refuses it. Override with a
throwaway v2 conf (fish, run from /tmp — comma needs nix-index DB populated):

```fish
cd /tmp
printf 'unqualified-search-registries = ["docker.io"]\n' > /tmp/reg.conf
set -x CONTAINERS_REGISTRIES_CONF /tmp/reg.conf
```

## Two inspects

**Manifest** — digest (for pinning), version label, arch list:

```fish
, skopeo inspect docker://ghcr.io/owner/app:latest \
  | grep -iE '"Digest"|"Created"|image.version|"Name"'
```

**Config** (`--config`) — the run-time facts that pick uid/harden/port:

```fish
, skopeo inspect --config docker://ghcr.io/owner/app:<tag-or-@digest> \
  | grep -iE '"User"|"WorkingDir"|"ExposedPorts"|Entrypoint|"Cmd"'
```

## Reading the result → nix knobs

| Inspect shows | Nix decision |
|---|---|
| `ExposedPorts: 20128/tcp` | `port = 20128;` |
| `User: "1000"` (or node/app uid) | `uid = 1000;` → keep-id maps to host srv |
| `User: ""`/root + entrypoint `chown ... && su-exec node` | inits as root, drops priv → `harden = false` (needs CHOWN/SETUID), `uid =` the final dropped uid |
| `Entrypoint: ["/entrypoint.sh"]` with s6/su-exec/gosu | s6/lsio-style → `harden = false` (see adding-services rule) |
| `"Digest": "sha256:..."` | pin internet-facing images by digest (unless user wants auto-update) |

Manifest digest is the **manifest-list** digest for multi-arch — pin that; podman
picks the arch. See `.claude/rules/adding-services.md` (keep-id/harden) and
`.claude/rules/srv-podman.md` (fully-qualified image names).
