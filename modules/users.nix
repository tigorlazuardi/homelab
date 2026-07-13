{ config, pkgs, ... }:
{
  # Login password for the human user (sops, same age key as before).
  sops.secrets."users/homeserver/password" = {
    neededForUsers = true;
    sopsFile = ../secrets/users.yaml;
  };

  # Grafana service-account token for the grafana MCP server. Loaded as an
  # EnvironmentFile on the herdr daemon (home/herdr-sessions.nix via osConfig) so
  # every claude session's .mcp.json can read ${GRAFANA_SERVICE_ACCOUNT_TOKEN}
  # without the token ever hitting the repo or the nix store. owner=homeserver →
  # the systemd --user service can read it.
  sops.secrets."grafana-mcp.env" = {
    sopsFile = ../secrets/grafana-mcp.env;
    format = "dotenv";
    key = "";
    owner = "homeserver";
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
      # read all journals (incl. srv user-unit logs) without sudo — read-only,
      # not a privilege escalation. Lets diagnostics run without root.
      "systemd-journal"
    ];
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPO1aSG3/1vrgEPgK038tZ8+ipz3gZqr9hRT0JUteJXY tigor@fort"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB/dGHD56+3qsLhUvmG4GeN8JrpYw7oGt0iQT+WkZzFu tigor@nexus"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGUdNT+Pr015Li6Jp9cb1vCghd2C8EnecYwSC98qQCxl tigor@envy"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKz9QiADKsexZdggCZpGuwBQp3yeZ4ulOVaTAQ5dx1tv tigor@windows"
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

  # homeserver → srv without a password. srv is treated as a tighter-permission
  # sub-account of the human user: it owns all rootless containers, so the operator
  # drives `sudo -u srv XDG_RUNTIME_DIR=/run/user/1001 podman …` constantly.
  # Scoped to runAs=srv only (NOT root) — this grants the human user the srv
  # identity, never privilege escalation to root. SETENV lets the inline
  # XDG_RUNTIME_DIR=… survive sudo's env reset. (cd /tmp first — srv can't chdir
  # into homeserver's 0700 home; see .claude/rules/srv-podman.md.)
  security.sudo.extraRules = [
    {
      users = [ "homeserver" ];
      runAs = "srv";
      commands = [
        {
          command = "ALL";
          options = [
            "NOPASSWD"
            "SETENV"
          ];
        }
      ];
    }
  ];

  # Per-user Home Manager scaffold (global settings live in configuration.nix).
  home-manager.users.homeserver = {
    imports = [
      ./home/git.nix
      ./home/lazygit.nix
      ./home/bun.nix
      ./home/agents.nix
      ./home/lazyvim
      ./home/systemd-srv.nix
      ./home/tuxedo.nix
      ./home/herdr-sessions.nix
      ./home/herdr-claude-retry.nix
      ./home/comma.nix
      ./home/pi-web.nix
      ./home/herdr-web-tui.nix
    ];
    home.username = "homeserver";
    home.homeDirectory = "/home/homeserver";
    home.stateVersion = "25.11";
  };
  home-manager.users.srv = {
    home.username = "srv";
    home.homeDirectory = "/home/srv";
    home.stateVersion = "25.11";
  };

  # Storage tiers — owned srv:media, setgid (2775) so new files inherit `media`.
  # See .claude/rules/storage.md. Per-app subdirs are created by each service;
  # here we only own the tier roots / shared trees.
  systemd.tmpfiles.rules = [
    # state (SSD) — config / db / index, high R/W. Per-app dirs under it.
    "d /var/mnt/state 2750 srv media -"
    # wolf (HDD) — durable but replaceable media + arr downloads. Downloads and
    # library share this filesystem → atomic move / hardlink on import.
    "d /var/mnt/wolf/media 2775 srv media -"
    "d /var/mnt/wolf/media/tv 2775 srv media -"
    "d /var/mnt/wolf/media/movies 2775 srv media -"
    "d /var/mnt/wolf/media/anime 2775 srv media -"
    "d /var/mnt/wolf/media/music 2775 srv media -"
    # arr download dir — named `torrents` to match the old deploy's container
    # path (/data/torrents) so carried qbit/arr configs + seeding resume untouched.
    "d /var/mnt/wolf/torrents 2775 srv media -"
    # nas (DYING HDD) — disposable downloads only (download-and-delete). Nothing
    # irreplaceable lives here; safe to lose when the disk fails.
    "d /var/mnt/nas/downloads 2775 srv media -"
    # fenrir (HDD) — sentimental / irreplaceable (immich photos, paperless docs).
    "d /var/mnt/fenrir 2775 srv media -"
  ];
}
