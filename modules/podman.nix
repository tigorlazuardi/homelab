{ pkgs, ... }:
{
  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
    defaultNetwork.settings.dns_enabled = true;
    dockerCompat = true;
  };

  # quadlet-nix: enables the system side. Rootless containers are declared under
  # `home-manager.users.srv.virtualisation.quadlet.containers.*` in services/*.
  virtualisation.quadlet.enable = true;

  # Podman ships a root auto-update oneshot linked into default.target. All
  # containers here are rootless under srv, whose timer below owns updates.
  systemd.services.podman-auto-update.wantedBy = [ ];

  # Rootless auto-update. The helper labels every container AutoUpdate=registry,
  # but that label is INERT without a timer to actually run `podman auto-update`.
  # Enable the daily rootless timer for the srv user (all app containers run under
  # srv). Only tag refs (e.g. :latest) update; digest-pinned images are skipped by
  # podman — which is exactly the "update internet-facing deliberately" policy in
  # conventions.md. Randomized delay so a wave of pulls doesn't stampede the batch
  # tier. auto-update restarts the quadlet unit and rolls back on a failed start.
  home-manager.users.srv.systemd.user = {
    services.podman-auto-update = {
      Unit = {
        Description = "Auto-update rootless podman containers";
        # Only the timer may start this expensive oneshot; Home Manager activation
        # must not start it directly while nixos-rebuild waits.
        RefuseManualStart = true;
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.podman}/bin/podman auto-update";
        ExecStartPost = "${pkgs.podman}/bin/podman image prune -f";
      };
    };
    timers.podman-auto-update = {
      Unit.Description = "Daily rootless podman auto-update";
      Timer = {
        OnCalendar = "daily";
        # Do not catch up a missed run while Home Manager reloads this timer during
        # nixos-rebuild switch; the next daily window performs the update.
        Persistent = false;
        RandomizedDelaySec = "45m";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
