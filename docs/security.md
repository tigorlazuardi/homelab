# Security model

Defense-in-depth for a personal, internet-facing (via Cloudflare/nginx) homeserver.

## Threat model (ranked)

1. **qbittorrent** — handles untrusted input (malicious torrents, web-UI RCE).
2. Internet-facing web apps → app vuln → RCE in a container.
3. `:latest` + auto-update → poisoned upstream image runs automatically.
4. Lateral movement after one container is popped.
5. Secret exposure.

## What the design gets right

- **Rootless** — container escape lands as unprivileged `srv`, not root.
- **userns (keep-id)** — even container-UID-0 maps to a host subuid.
- No root container daemon/socket to hijack.
- Edge services (nginx/adguard/wireguard) split out from the app user.

## The known weakness — flat blast radius

One `srv` user owns all data (group `media`). A container that breaks out to
`srv` can read/write **all** data + tamper with every service's state. We chose
this for simplicity over per-service users. Claw back isolation with:

### 1. Read-only mounts (biggest single mitigation)

Readers mount data `:ro`; only writers get `:rw`.

```
qbittorrent, *arr   → /srv/data/downloads  :rw
jellyfin, navidrome → /srv/data/media      :ro   (can't ransomware the library)
immich              → old originals        :ro   (External Library)
```

Host data stays `srv:media`, the human user still has full access — only the
container's view is restricted.

### 2. qbittorrent = hostile tenant

- Consider a dedicated sub-user even within the shared model.
- `downloads/` only; no access to other services' `state/`.
- Web UI loopback + behind nginx auth; never expose the torrent UI directly.
- Route torrent traffic via the VPN interface.

## Per-container hardening (declarative in quadlet)

- `dropCapabilities = [ "all" ]`, add back only what's needed.
- `noNewPrivileges = true`.
- `readOnly = true` + `tmpfses` for scratch (where the app allows).
- Never `--privileged`; publish to `127.0.0.1` only — nginx is sole ingress.
- Keep the default seccomp profile.

## Secrets

- sops/age only; **never** plaintext in the repo.
- Secret files mode `0400`, **outside** the `media`-readable data tree.
- Mounted `:ro` into the one container that needs them.

## Supply chain (the auto-update tension)

Auto-update = patch velocity vs running a poisoned image. Resolve per tier:
- Internet-facing/edge images → pin by **digest**, update deliberately.
- Internal low-risk → `autoUpdate="registry"` on `:latest` is fine.

## Ingress

- Prefer **Cloudflare Tunnel** → no inbound 80/443, origin hidden. Otherwise
  CF-only firewall + the `set_real_ip_from` ranges (configured in nginx).
- All service UIs loopback; auth at nginx; SSH key-only over WireGuard/LAN.

## Caveat

Rootless/userns is **defense-in-depth, not a wall** — kernel LPE can cross it.
Keep the kernel current; don't treat "rootless" as "safe to expose anything".

## Publishing this repo

- Encrypted sops files are safe to publish; `.sops.yaml` holds only public keys.
- Private age key (`/opt/age-key.txt`) is never committed (see `.gitignore`).
- Fresh git history = no plaintext-secret liability from the old repo's past.
- Run `gitleaks`/`trufflehog` before the first push.
