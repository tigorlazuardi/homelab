{ config, pkgs, ... }:
{
  # Login password for the human user (sops, same age key as before).
  sops.secrets."users/homeserver/password" = {
    neededForUsers = true;
    sopsFile = ../secrets/users.yaml;
  };

  users.groups = {
    homeserver = { };
    srv = { };
    media = { }; # shared group: human user + srv both members → friction-free data access
  };

  # Human user — interactive (SSH, samba). In `media` so it can read/write all data.
  users.users.homeserver = {
    isNormalUser = true;
    hashedPasswordFile = config.sops.secrets."users/homeserver/password".path;
    extraGroups = [
      "wheel"
      "homeserver"
      "media"
    ];
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPO1aSG3/1vrgEPgK038tZ8+ipz3gZqr9hRT0JUteJXY tigor@fort"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB/dGHD56+3qsLhUvmG4GeN8JrpYw7oGt0iQT+WkZzFu tigor@nexus"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGUdNT+Pr015Li6Jp9cb1vCghd2C8EnecYwSC98qQCxl tigor@envy"
    ];
    linger = true;
  };

  # Dedicated non-login service user — runs ALL rootless app containers.
  # linger: user services start at boot without login.
  # autoSubUidGidRange: allocate subuid/subgid for rootless user namespaces.
  users.users.srv = {
    isNormalUser = true;
    group = "srv";
    extraGroups = [ "media" ];
    home = "/home/srv";
    createHome = true;
    shell = pkgs.bashInteractive;
    linger = true;
    autoSubUidGidRange = true;
  };

  # Per-user Home Manager scaffold (global settings live in configuration.nix).
  home-manager.users.homeserver = {
    home.username = "homeserver";
    home.homeDirectory = "/home/homeserver";
    home.stateVersion = "25.11";
  };
  home-manager.users.srv = {
    home.username = "srv";
    home.homeDirectory = "/home/srv";
    home.stateVersion = "25.11";
  };

  # Shared data tree — owned srv:media, setgid (2775) so new files inherit `media`.
  # Keep downloads + media on the SAME filesystem for atomic move / hardlink.
  systemd.tmpfiles.rules = [
    "d /srv/data 2775 srv media -"
    "d /srv/data/downloads 2775 srv media -"
    "d /srv/data/media 2775 srv media -"
    "d /srv/data/media/movies 2775 srv media -"
    "d /srv/data/media/tv 2775 srv media -"
    "d /srv/data/media/music 2775 srv media -"
    "d /srv/data/state 2750 srv media -" # per-app config/db (not shared widely)
  ];
}
