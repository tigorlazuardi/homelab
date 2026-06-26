---
paths:
  - services/zellij-web.nix
  - modules/home/claude-sessions.nix
---

# zellij web (browser + remote-attach access to sessions)

Native `zellij web` server (services/zellij-web.nix) serving the homeserver
user's durable sessions (modules/home/claude-sessions.nix). Hard-won constraints
— violating any of these silently breaks attach:

## web_sharing MUST be "on" — and it lives OUTSIDE this repo

zellij defaults `web_sharing "off"`. With it off, every session **rejects** web
attach with `"not allowed to attach to this session"` (the browser then loops on
`CONNECTION LOST`; the server log shows `Received unknown message from client` →
`over 1000 consecutive unknown messages, logging client out` — that is the
SYMPTOM of the rejected half-open ws, not a proxy bug).

The fix is `web_sharing "on"` in the homeserver `~/.config/zellij/config.kdl`,
which is **intentionally unmanaged** (not in this repo). So a fresh machine will
NOT have it — set it by hand. There is no clean way to pass it via the
`--new-session-with-layout` launcher, and managing the whole config.kdl in nix is
declined (it carries the hand-tuned keybind legend). This is a known repro gap;
keep it documented in the zellij-web.nix header.

## Auth is the zellij token, NOT tinyauth — they are mutually exclusive

Do NOT put `tinyauth.enable = true` on the zellij vhost. tinyauth is browser-SSO
forward-auth; the `zellij attach <url> --token` CLI carries only the zellij token
(no SSO cookie), so a tinyauth gate would 401 native remote-attach. zellij's own
login token (hashed, revocable, read-only variant) IS the gate. Create it once
post-deploy (`zellij web --create-token`), store in a password manager — shown
once, unrecoverable.

## Bind loopback + reverse-proxy hardening

- Bind `127.0.0.1` only; never open the port in the firewall. nginx is the sole
  ingress and terminates public TLS (loopback hop stays plaintext, no cert to
  zellij). 8082 (zellij default) is taken by ytptube — use 7682.
- zellij web has **no built-in rate-limiting**; the docs require a reverse proxy.
  Keep the nginx `limit_req` zone on the vhost.

## Session start order

Session units must start `After=zellij-web.service`: a session only opts into web
sharing "if the web server is online" **at its start**. Sessions created before
the server is up reject attach until restarted (`systemctl --user restart 'zellij-*'`).
