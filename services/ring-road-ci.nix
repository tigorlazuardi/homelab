# Native self-hosted GitHub Actions runner for trusted internal Ring Road CI.
# Trust ceiling: private repo + reviewed internal PRs only. Use a VM before
# accepting fork/external/untrusted workflows.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  name = "ring-road-ci";
  user = "ring-road-ci";
  uid = 1500;
  runtimeDir = "/run/user/${toString uid}";
  podmanSocket = "unix://${runtimeDir}/podman/podman.sock";
  nixPath = "nixpkgs=${pkgs.path}";
  podmanPackage = config.virtualisation.podman.package;
  productionPaths = [
    "-/home/srv"
    "-/run/user/1001"
    "-/srv/data"
    "-/var/lib/containers"
    "-/var/mnt/fenrir"
    "-/var/mnt/nas"
    "-/var/mnt/state"
    "-/var/mnt/wolf"
  ];

  # Pinned Podman module keeps its dockerCompat output private.
  dockerCompat =
    pkgs.runCommand "${podmanPackage.pname}-docker-compat-${podmanPackage.version}" { }
      ''
        mkdir -p $out/bin
        ln -s ${podmanPackage}/bin/podman $out/bin/docker
      '';
in
{
  sops.secrets."ring-road-ci/runner-pat" = {
    sopsFile = ../secrets/ring-road-ci.yaml;
    key = "runner_pat";
    owner = user;
    group = user;
    mode = "0400";
  };

  # GitHub runner currently bundles Node 20 for action compatibility.
  nixpkgs.config.permittedInsecurePackages = [
    "nodejs-20.20.2"
    "nodejs-slim-20.20.2"
  ];

  users.groups.${user} = { };
  users.users.${user} = {
    isSystemUser = true;
    inherit uid;
    group = user;
    home = "/home/${user}";
    homeMode = "0700";
    createHome = true;
    linger = true;
    autoSubUidGidRange = true;
  };

  # Runner owns this user manager and rootless store; srv's production Podman
  # socket/store remain unreachable through user, mode, and mount separation.
  systemd.user.sockets.podman.wantedBy = lib.mkForce [ ];
  home-manager.users.${user} = {
    home.username = user;
    home.homeDirectory = "/home/${user}";
    home.stateVersion = "25.11";
    # Scope daemon sandbox to CI user's manager; a global user-unit override would
    # also hide production paths from srv's production Podman daemon.
    xdg.configFile."systemd/user/podman.service.d/10-ring-road-ci-sandbox.conf".text = ''
      [Service]
      InaccessiblePaths=${lib.concatStringsSep " " productionPaths}
    '';
    systemd.user = {
      sockets.podman = {
        Unit.Description = "Ring Road CI rootless Podman API socket";
        Socket = {
          ListenStream = "%t/podman/podman.sock";
          SocketMode = "0600";
          DirectoryMode = "0700";
        };
        Install.WantedBy = [ "sockets.target" ];
      };
      # Podman ships this timer globally; disable it only for CI user.
      timers.podman-auto-update.Install.WantedBy = lib.mkForce [ ];
    };
  };

  services.github-runners.${name} = {
    enable = true;
    url = "https://github.com/tigorlazuardi/ring-road";
    tokenFile = config.sops.secrets."ring-road-ci/runner-pat".path;
    replace = true;
    name = "ring-road-ci-native";
    extraLabels = [
      "native"
      "bun"
      "podman"
      "homelab"
    ];
    nodeRuntimes = [
      "node20"
      "node24"
    ];
    extraPackages = [
      pkgs.bun
      pkgs.nodejs_24
      podmanPackage
      dockerCompat
      pkgs.unzip
      pkgs.git
      pkgs.gh
      pkgs.openssh
      pkgs.cacert
      config.nix.package
    ];
    inherit user;
    group = user;
    serviceOverrides = {
      Environment = [
        "HOME=/home/${user}"
        "XDG_RUNTIME_DIR=${runtimeDir}"
        "DOCKER_HOST=${podmanSocket}"
        "CONTAINER_HOST=${podmanSocket}"
        "NIX_PATH=${nixPath}"
      ];
      # Shared user slice keeps runner, API daemon, and container descendants
      # inside one resource budget.
      Slice = "user-${toString uid}.slice";
      ProtectHome = false;
      ReadWritePaths = [ "/home/${user}" ];
      InaccessiblePaths = productionPaths;
      # Workflows run rootless containers, including custom networks and named
      # volumes. Keep runner unprivileged while allowing required namespaces and
      # delegated cgroups below its dedicated user slice.
      PrivateUsers = false;
      ProtectControlGroups = false;
      RestrictNamespaces = [
        "user"
        "mnt"
        "pid"
        "ipc"
        "uts"
        "cgroup"
      ];
      SystemCallFilter = lib.mkForce [
        "~@clock"
        "~@cpu-emulation"
        "~@module"
        "~@obsolete"
        "~@raw-io"
        "~@reboot"
        "~setdomainname"
        "~sethostname"
      ];
    };
  };

  systemd.services = {
    ring-road-ci-podman-socket = {
      description = "Start Ring Road CI rootless Podman socket";
      after = [ "user@${toString uid}.service" ];
      requires = [ "user@${toString uid}.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.systemd}/bin/systemctl --user --machine=${user}@.host start podman.socket";
      };
    };
    github-runner-ring-road-ci = {
      after = [ "ring-road-ci-podman-socket.service" ];
      requires = [ "ring-road-ci-podman-socket.service" ];
      serviceConfig = {
        Restart = lib.mkForce "on-failure";
        RestartSec = "10s";
      };
    };
  };

  systemd.slices."user-${toString uid}".sliceConfig = {
    CPUQuota = "400%";
    CPUWeight = 10;
    MemoryHigh = "8G";
  };

  # ponytail: Podman filters implement 7d retention without custom cleanup code;
  # preserve volumes by pruning only stopped containers, images, and networks.
  systemd.services.ring-road-ci-podman-prune = {
    description = "Prune Ring Road CI rootless Podman resources older than 7 days";
    after = [ "ring-road-ci-podman-socket.service" ];
    requires = [ "ring-road-ci-podman-socket.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = user;
      Group = user;
      ExecStart = pkgs.writeShellScript "ring-road-ci-podman-prune" ''
        set -euo pipefail
        status=0
        trap 'echo "Ring Road CI Podman prune result status=$status"' EXIT
        echo "Ring Road CI Podman prune starting"
        ${podmanPackage}/bin/podman container prune --force --filter until=168h || status=$?
        if (( status == 0 )); then
          ${podmanPackage}/bin/podman image prune --all --force --filter until=168h || status=$?
        fi
        if (( status == 0 )); then
          ${podmanPackage}/bin/podman network prune --force --filter until=168h || status=$?
        fi
        exit "$status"
      '';
    };
    environment = {
      HOME = "/home/${user}";
      XDG_RUNTIME_DIR = runtimeDir;
      CONTAINER_HOST = podmanSocket;
    };
  };
  systemd.timers.ring-road-ci-podman-prune = {
    description = "Weekly Ring Road CI rootless Podman prune";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };

  # Fixed CI integration ports are job-local loopback listeners. Single runner
  # instance means at most one job can own 55432, 59000, and 59001 at a time.
}
