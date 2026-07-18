{
  config,
  inputs,
  ...
}:
{
  imports = [ inputs.switchd.nixosModules.default ];

  sops.secrets = {
    "switchd/bot-token" = {
      sopsFile = ../secrets/switchd.yaml;
      key = "bot_token";
      mode = "0400";
      restartUnits = [ "switchd.service" ];
    };
    "switchd/allowed-user-ids" = {
      sopsFile = ../secrets/switchd.yaml;
      key = "allowed_user_ids";
      mode = "0400";
      restartUnits = [ "switchd.service" ];
    };
    "switchd/chat-id" = {
      sopsFile = ../secrets/switchd.yaml;
      key = "chat_id";
      mode = "0400";
      restartUnits = [ "switchd.service" ];
    };
  };

  services.switchd = {
    enable = true;
    # Upstream options require absolute paths, so systemd's %d specifier cannot be used.
    botTokenFile = "/run/credentials/switchd.service/bot-token";
    allowedUserIdsFile = "/run/credentials/switchd.service/allowed-user-ids";
    chatIdFile = "/run/credentials/switchd.service/chat-id";
    repoDir = "/home/homeserver/homelab";
    flakeRef = "/home/homeserver/homelab#homeserver";
  };

  systemd.services.switchd.serviceConfig.LoadCredential = [
    "bot-token:${config.sops.secrets."switchd/bot-token".path}"
    "allowed-user-ids:${config.sops.secrets."switchd/allowed-user-ids".path}"
    "chat-id:${config.sops.secrets."switchd/chat-id".path}"
  ];

  users.users.homeserver = {
    extraGroups = [ config.services.switchd.group ];
    homeMode = "0710";
  };
  environment.systemPackages = [ config.services.switchd.package ];

  # ponytail: z reapplies ownership on the existing home; d only created missing paths.
  systemd.tmpfiles.rules = [
    "z /home/homeserver 0710 homeserver ${config.services.switchd.group} -"
  ];
}
