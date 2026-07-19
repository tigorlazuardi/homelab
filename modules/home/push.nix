{
  pkgs,
  config,
  ...
}:
let
  push = pkgs.callPackage ../../packages/push.nix { };
  home = config.home.homeDirectory;
  configFile = "${home}/.push/config.toml";
  start = pkgs.writeShellScript "push-start" ''
    if [ ! -f ${configFile} ]; then
      echo "push: config missing at ${configFile}; unit remains dormant"
      exit 0
    fi
    exec ${push}/bin/push --config ${configFile}
  '';
in
{
  home.packages = [ push ];

  # TODO(cutover): After switch, inspect generated push.service and confirm config ownership/readability, `push doctor`, and one Telegram round trip.
  systemd.user.services.push = {
    Unit.Description = "Push personal assistant gateway";
    Install.WantedBy = [ "default.target" ];
    Service = {
      Type = "simple";
      WorkingDirectory = home;
      ExecStart = start;
      Restart = "on-failure";
      RestartSec = 10;
      # ponytail: config stays operator-owned so secrets never enter Nix store; add sops only if unattended secret provisioning is required.
      Environment = [
        "PATH=${push}/bin:/etc/profiles/per-user/homeserver/bin:/run/current-system/sw/bin"
      ];
    };
  };
}
