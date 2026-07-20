# Jellyfin — media server (read-only consumer of the wolf library). Own login
# page, so NOT behind tinyauth (like immich/grafana). linuxserver image (same
# family as the working *arr stack; the official image SIGSEGVs under our
# rootless user-mapping).
#
# The LSIO `abc` user is baked into the render/video groups (it's a transcoder
# image); its s6 init calls setgroups() for them. Under keep-id only uid/gid 1000
# are mapped, so those gids are unmapped → EPERM ("s6-applyuidgid: unable to set
# supplementary group list: Operation not permitted") → crash-loop. The DEFAULT
# rootless userns (userns=null) maps the full subuid/subgid range, so every gid
# abc uses resolves and setgroups succeeds. Trade-off: jellyfin writes as a
# mapped subuid (not srv) — fine, /config is its own and /media is read-only +
# world-readable. Intel Quick Sync HW transcode via /dev/dri/renderD128 (see extraContainerConfig).
{ pkgs, ... }:
{
  homelab.containers.jellyfin = {
    image = "lscr.io/linuxserver/jellyfin:latest";
    port = 8096;
    subdomain = "jellyfin";
    networks = [ "arr" ];
    userns = null; # default rootless userns → full gid range mapped (s6 setgroups)
    harden = false; # linuxserver s6 init needs caps
    # Interactive media slice: jellyfin wins over batch media (ytptube, immich) and
    # over coding sessions when actively streaming (see services/media-slice.nix and
    # modules/cpu-budget.nix). CPUWeight within media-interactive.slice not needed
    # since jellyfin is the only member.
    serviceConfig = {
      Slice = "media-interactive.slice";
      # ponytail: user units cannot depend on system mount units; skip startup
      # rather than bind the pre-mount directory. System hook below handles the
      # opposite race when Jellyfin was already active before wolf appeared.
      ExecCondition = "${pkgs.util-linux}/bin/mountpoint --quiet /var/mnt/wolf";
    };
    # HW transcoding via Intel Quick Sync (UHD 730). renderD128 is world-rw
    # (666), same node immich uses — no render-group mapping needed under the
    # default rootless userns. Enable QSV in Jellyfin Admin → Playback after switch.
    extraContainerConfig = {
      devices = [ "/dev/dri/renderD128" ];
    };
    volumes = [
      "/var/mnt/state/jellyfin/config:/config"
      "/var/mnt/state/jellyfin/cache:/cache"
      # library is read-only to Jellyfin — arr owns writes. Matches new layout.
      "/var/mnt/wolf/media:/media:ro"
      # NOTE: personal qbit library on nas (/media-personal) removed 2026-07-03 —
      # nas (sdc, WD) is dying with 36 pending sectors; jellyfin's boot library
      # scan of it kept hitting UNC reads → ATA link resets → host-wide I/O stall
      # → SSH/network dead → physical reboot. See modules/disk-error-recovery.nix.
      # Remove the stale "media-personal" library in Jellyfin Admin → Libraries.
      # new qbit downloads
      "/var/mnt/wolf/torrents:/torrents:ro"
    ];
    environments = {
      TZ = "Asia/Jakarta";
      PUID = "1000";
      PGID = "1000";
      UMASK = "002";
      JELLYFIN_PublishedServerUrl = "https://jellyfin.tigor.web.id";
    };
    # Jellyfin needs WebSocket upgrade for live sync / remote control.
    nginx.extraConfig = ''
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
    '';
    # config/cache are owned by the SUBUID that container uid 1000 (abc) maps to
    # under the default rootless userns — srv's subuid base (165536, = 100000 +
    # (1001-1000-... )·65536 for srv uid 1001) + (1000-1) = 166535. They must NOT
    # be owned by srv, or jellyfin (running as 166535) can't write. Pinning the
    # numeric owner here keeps systemd-tmpfiles from clobbering it back to srv on
    # every boot/switch. If srv's uid (→ subuid base) ever changes, update 166535.
    tmpfiles = [
      "d /var/mnt/state/jellyfin 0750 srv media -"
      "d /var/mnt/state/jellyfin/config 0700 166535 166535 -"
      "d /var/mnt/state/jellyfin/cache 0700 166535 166535 -"
    ];
  };

  # Bridge system mount lifecycle → srv user manager. A rootless container keeps
  # its original bind-mount inode when wolf mounts later. `start` is idempotent:
  # it starts Jellyfin if ExecCondition skipped earlier, while an already-active
  # unit is restarted first so Podman recreates the bind mount.
  systemd.services.jellyfin-refresh-wolf-mount = {
    description = "Refresh Jellyfin bind mounts after wolf mounts";
    requires = [
      "var-mnt-wolf.mount"
      "user@1001.service"
    ];
    after = [
      "var-mnt-wolf.mount"
      "user@1001.service"
    ];
    wantedBy = [ "var-mnt-wolf.mount" ];
    serviceConfig = {
      Type = "oneshot";
      User = "srv";
      Environment = "XDG_RUNTIME_DIR=/run/user/1001";
      ExecStart = pkgs.writeShellScript "refresh-jellyfin-wolf-mount" ''
        ${pkgs.systemd}/bin/systemctl --user try-restart jellyfin.service
        ${pkgs.systemd}/bin/systemctl --user start jellyfin.service
      '';
    };
  };
}
