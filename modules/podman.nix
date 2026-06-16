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
}
