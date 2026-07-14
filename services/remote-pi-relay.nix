# remote-pi-relay — WebSocket relay for Remote Pi (jacobmoura7/remote-pi-relay).
# End-to-end-encrypted message broker between a Pi coding-agent instance and its
# paired mobile device; the relay never reads payloads (E2E crypto), it only
# forwards frames and persists Owner-signed mesh blobs to /data/mesh.db.
#
# Private vhost only: LAN + wireguard + tailscale, deny all (no auth gate, no API
# key — access controlled purely at nginx), matching the docs' "layer behind a VPN"
# guidance. Serves the WS upgrade, /health, and /mesh/<owner_pk_hash> on port 3000.
#
# The image runs as root (User unset) — a static `relay` binary, no su-exec/gosu
# privilege drop — so it needs the default rootless userns (`userns = null`):
# container root maps to host srv, /data/mesh.db lands owned by srv. No caps needed
# (binds unprivileged 3000, writes a file) so hardening stays on. Image pinned by
# manifest-list digest (crypto component → deliberate supply-chain updates; podman
# auto-update skips digest pins).
{
  homelab.containers.remote-pi-relay = {
    image = "docker.io/jacobmoura7/remote-pi-relay@sha256:b88b1984a20170debf569937b5a1245dd325b38aba3ef46f327962b733be446a"; # v0.2.2
    port = 3000; # REMOTEPI_RELAY_PORT default; nginx vhost remote-pi-relay.tigor.web.id auto-created
    userns = null; # image runs as root → default rootless userns maps to host srv
    volumes = [ "/var/mnt/state/remote-pi-relay:/data" ]; # mesh.db (owner-signed blobs) → state tier
    environments = { TZ = "Asia/Jakarta"; }; # REMOTEPI_RELAY_PORT / REMOTEPI_MESH_DB_PATH already baked in image
    private = true; # LAN + wireguard + tailscale only (homelab.nginx.trustedRanges), deny all
    tmpfiles = [ "d /var/mnt/state/remote-pi-relay 0750 srv srv -" ];
  };
}
