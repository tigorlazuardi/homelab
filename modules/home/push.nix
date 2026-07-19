{
  pkgs,
  config,
  osConfig,
  ...
}:
let
  push = pkgs.callPackage ../../packages/push.nix { };
  home = config.home.homeDirectory;
  configFile = osConfig.sops.templates."push.toml".path;
  assistantRoot = "${home}/assistant";
  pushCodex = pkgs.writeShellScriptBin "codex" ''
    exec ${pkgs.codex}/bin/codex --model gpt-5.6-luna --config model_reasoning_effort=high "$@"
  '';
  start = pkgs.writeShellScript "push-start" ''
    ${push}/bin/push init ${assistantRoot}
    if ! ${push}/bin/push doctor --config ${configFile}; then
      echo "push: setup incomplete; fix config/auth, then restart push.service"
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
      Environment = [
        "PATH=${pushCodex}/bin:${push}/bin:/etc/profiles/per-user/homeserver/bin:/run/current-system/sw/bin"
      ];
    };
  };
}
