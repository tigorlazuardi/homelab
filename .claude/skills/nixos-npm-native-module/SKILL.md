---
name: nixos-npm-native-module
description: Running an npm CLI/tool that has a native (node-gyp) addon as a NixOS systemd service. Use whenever adding or debugging a Node.js service installed at runtime via `bun install -g` / `npm i -g` on this homelab (pi-web/node-pty, or any package depending on node-pty, better-sqlite3, node-gyp-build, bcrypt, etc.), especially when it crashes at startup with "Failed to load native module" / "Cannot find module '.../*.node'". Covers why bun skips the build, the offline node-gyp rebuild fix against nix nodejs headers, and the ExecStartPre pattern.
---

# NixOS + runtime-installed npm tool with a native module

The homelab runs some Node tools as `systemd --user` services that install
themselves at runtime via `bun install -g` in an `ExecStartPre` (deliberately
non-deterministic, always-latest — see `modules/home/pi-web.nix`, mirrors
`modules/home/herdr-*`). This works fine for pure-JS packages. It **breaks** the
moment a dependency ships a **native (node-gyp) addon**.

## The trap: `bun install -g` does not build native addons

`bun install` **does not run package lifecycle scripts** (`postinstall`/`install`)
by default — bun blocks them as a security measure. Native npm packages
(`node-pty`, `better-sqlite3`, `bcrypt`, anything using `node-gyp-build`) rely on
that postinstall to fetch a prebuild **or** compile the `.node` binary. bun skips
it, so the binary is never produced and the tool dies at startup:

```
Error: Failed to load native module: pty.node, checked: build/Release,
build/Debug, prebuilds/linux-x64: Cannot find module './prebuilds/linux-x64//pty.node'
```

**`bun pm trust` does NOT help for a transitive dep.** bun's trust gate only
applies to *direct/top-level* dependencies. `node-pty` is a transitive dep of
`@jmfederico/pi-web`, so `bun pm untrusted` doesn't even list it and there is no
trust lever to pull. Don't waste time there.

## The fix: compile with node-gyp against the nix nodejs headers (offline)

After the `bun install -g`, detect the broken/missing native module and rebuild it
with `node-gyp`, pointing `npm_config_nodedir` at the **same** `pkgs.nodejs`
derivation the runtime `node` resolves to (ABI must match, and this makes the
build **offline** — node-gyp uses the store's bundled headers instead of trying to
download them, which a sandboxed/isolated service can't do):

```nix
let
  piWebInstall = pkgs.writeShellScript "pi-web-install" ''
    set -euo pipefail
    bun install -g @jmfederico/pi-web@${piWebVersion} @mariozechner/pi-coding-agent@${piWebVersion}

    ptyDir="${home}/.bun/install/global/node_modules/node-pty"
    if [ -d "$ptyDir" ] && ! node -e 'require(process.argv[1])' "$ptyDir" >/dev/null 2>&1; then
      echo "pi-web: node-pty native module missing/broken — building via node-gyp" >&2
      ( cd "$ptyDir" && npm_config_nodedir=${pkgs.nodejs} ${pkgs.node-gyp}/bin/node-gyp rebuild )
      node -e 'require(process.argv[1])' "$ptyDir"
    fi
  '';
in
# ...
systemd.user.services.<name>-sessiond.Service.ExecStartPre = "${piWebInstall}";
```

Key points:
- **Guard on the actual load** (`node -e require(...)`), not on file existence — makes
  it idempotent (skips the rebuild when already good) and self-healing (rebuilds
  after a version bump changes the ABI). Verified: 2nd run skips the branch.
- **`npm_config_nodedir=${pkgs.nodejs}`** → offline compile, ABI-matched to the node
  that runs the service. Do NOT rely on node-gyp downloading headers.
- Add **`pkgs.node-gyp`** to reference; `gcc` + `python3` + `gnumake` must be
  reachable (already in `modules/home/agents.nix` home.packages here). `nix-ld`
  (`modules/nix-ld.nix`) is on, but a nix-gcc-compiled `.node` links to nix libs
  and loads under `node` without needing it.
- **Fail loud** (`set -euo pipefail`, no `-` prefix) so a first-ever build failure
  surfaces instead of silently starting a binary-less service.

## Multi-daemon tools: get the systemd coupling right

Some of these tools are **two processes** (e.g. pi-web = `pi-web-sessiond` daemon +
`pi-web-server`), talking over a unix socket (default `$HOME/.pi-web/sessiond.sock`
— same `$HOME` → both agree, don't override the socket path).

- Put the install/build `ExecStartPre` on the **daemon** unit (the install gate).
- The server is a per-request proxy to the daemon socket — it does **not** need to
  die when the daemon restarts. Couple them with **`Wants` + `After`**, NOT
  `Requires`/`PartOf`. `PartOf` propagates the daemon's stop to the server on a
  `switch`/restart and does **not** restart it → the server stays down → `nginx 502`.
  (Learned the hard way: `PartOf` dropped the pi-web server on every switch.)

## Symptom → cause quick map

| Symptom | Cause |
|---|---|
| `nginx 502`, `ss -tlnp` shows nothing on the port | the server process is down |
| `502` in the **app's own** JSON logs on `/api/machines/local/*` | server up, **daemon** (socket) down |
| daemon `systemctl --user` NRestarts climbing, `Failed to load native module` | native addon never built (the bun trap above) |
| server down after a `nixos-rebuild switch`, daemon up | `PartOf`/`Requires` coupling — use `Wants`+`After` |
