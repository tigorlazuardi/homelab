# ring-road-ci — dedicated systemd-nspawn NixOS container running a self-hosted
# GitHub Actions runner for the PRIVATE repo tigorlazuardi/ring-road, with nested
# rootless podman as the CI container backend.
#
# WHY nspawn (not a host-level services.github-runners): CI workflows pull and run
# arbitrary container images / `docker build`. Doing that with a podman backend on
# the host would pollute the host's image store, networks, and cgroups. An nspawn
# guest is the isolation boundary — the host stays clean, and the runner + its
# podman live entirely inside /var/lib/nixos-containers/ring-road-ci.
#
# NOT a caller of vpn-nspawn-box.nix — that factory ships office VPN + tailscale +
# herdr coding sessions + a huge dev toolchain, none of which a CI runner needs.
# This is a lean, purpose-built box: privateNetwork egress (via the existing
# ve-+ NAT the office boxes already set up), rootless podman, and the runner.
#
# Credential model (decided): a fine-grained PAT (repo: ring-road only,
# permissions: Administration RW + Actions RW) minted via `gh`, stored encrypted
# in secrets/ring-road-ci.yaml, decrypted on the HOST by sops-nix and bind-mounted
# read-only into the guest. The github-runner module uses the PAT to obtain and
# REFRESH runner-registration tokens itself, so the runner survives reboots with
# no manual re-registration. gh remains the way you mint/rotate that PAT.
#
# One-time setup (see bottom of file for the exact commands).
{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:
let
  name = "ring-road-ci";

  # Fresh /24 — distinct from bareksa (10.100), strategix (10.101), wireguard
  # (10.0.0.0/24) and the tailnet (100.64.0.0/10).
  hostAddress = "10.102.0.1";
  localAddress = "10.102.0.2";

  # Runner runs as this unprivileged guest user; rootless podman + linger below.
  # uid chosen to NOT collide with the host's homeserver(1000)/srv(1001) under
  # nspawn's identity uid mapping (no privateUsers here), and readable by the
  # world-readable bind-mounted PAT.
  ciUid = 1500;

  # Host path of the decrypted PAT (sops writes into /run/secrets). Bind-mounted
  # into the guest at patGuestPath below.
  patHostPath = config.sops.secrets."ring-road-ci/runner-pat".path;
  patGuestPath = "/run/ring-road-ci-pat";
in
{
  # ── Host-side sops secret: the fine-grained PAT ──────────────────────────────
  # World-readable file (0444) BUT it lives in /run/secrets, a root-only-traversable
  # dir on the host, so it is not exposed host-side. The bind mount points directly
  # at the file so the guest CI user can read it. Trade-off accepted: the PAT is
  # readable by any process INSIDE this single-purpose throwaway CI guest; it is
  # fine-grained + scoped to ring-road only, so blast radius is minimal. Rotate via
  # gh if ever needed.
  sops.secrets."ring-road-ci/runner-pat" = {
    sopsFile = ../secrets/ring-road-ci.yaml;
    key = "runner_pat";
    mode = "0444";
  };

  # ── The nspawn container ─────────────────────────────────────────────────────
  containers.${name} = {
    autoStart = true;

    # Own netns + /24; egress rides the ve-+ NAT + trustedInterfaces the office
    # boxes already declare in vpn-nspawn-box.nix (ve-ring-road-ci matches ve-+).
    privateNetwork = true;
    inherit hostAddress localAddress;

    # /dev/fuse for envfs (/usr/bin/env FHS shim that node/npm shebangs need) and
    # for rootless podman's fuse-overlayfs storage driver. Same wiring the office
    # boxes use — nspawn's minimal /dev has no /dev/fuse, so bind it in + allow it.
    allowedDevices = [
      {
        node = "/dev/fuse";
        modifier = "rwm";
      }
    ];
    bindMounts."/dev/fuse" = {
      hostPath = "/dev/fuse";
      isReadOnly = false;
    };

    # PAT: host-decrypted sops secret, mounted read-only.
    bindMounts.${patGuestPath} = {
      hostPath = patHostPath;
      isReadOnly = true;
    };

    # Pull bun/node/etc from the same nixpkgs pin the host uses.
    specialArgs = { inherit inputs; };

    config =
      { pkgs, ... }:
      {
        # No inbound path is needed — manage the box with `machinectl shell`. So no
        # sshd, no tailscale. Egress-only.

        # CI user: unprivileged, lingering (so its rootless podman user manager +
        # /run/user/1500 exist without an interactive login).
        users.users.ci = {
          isNormalUser = true;
          uid = ciUid;
          linger = true;
          # subuid/subgid range for rootless podman is auto-allocated
          # (users.users.<name>.autoSubUidGidRange defaults on for normal users).
        };

        # Rootless podman as the CI backend. dockerCompat gives a `docker` shim so
        # workflows that call `docker build`/`docker run` work unchanged; the
        # runner points DOCKER_HOST at the rootless socket (below).
        virtualisation.podman = {
          enable = true;
          dockerCompat = true;
          defaultNetwork.settings.dns_enabled = true;
        };

        # Rootless podman user socket — this is what DOCKER_HOST targets. podman
        # ships the user unit; enable it in every user manager (only the lingering
        # `ci` user actually runs one here, so scope is effectively just ci).
        systemd.user.sockets.podman.wantedBy = [ "sockets.target" ];

        # ── The self-hosted runner ───────────────────────────────────────────────
        services.github-runners.${name} = {
          enable = true;
          url = "https://github.com/tigorlazuardi/ring-road";
          tokenFile = patGuestPath; # fine-grained PAT → module refreshes reg tokens
          replace = true; # re-register cleanly if a stale runner with this name exists
          name = "ring-road-ci-nspawn";
          extraLabels = [
            "nspawn"
            "bun"
            "podman"
            "homelab"
          ];
          # Runtimes CI jobs use. bun@1.2.0 + node>=24 per ring-road's package.json;
          # git/gh for checkout + private submodules; the toolchain FHS shims come
          # from nix-ld/envfs below.
          extraPackages = with pkgs; [
            bun
            nodejs_24
            git
            gh
            openssh
            cacert
          ];
          user = "ci";
          # Point docker/podman calls at the rootless socket + give podman a HOME.
          serviceOverrides.Environment = [
            "XDG_RUNTIME_DIR=/run/user/${toString ciUid}"
            "DOCKER_HOST=unix:///run/user/${toString ciUid}/podman/podman.sock"
            "HOME=/home/ci"
          ];
        };

        # Unpatched dynamic binaries (mise/asdf toolchains, downloaded tools, LSPs)
        # + /usr/bin/env — mirrors the office boxes.
        programs.nix-ld.enable = true;
        services.envfs.enable = true;

        # CA bundle + git for the runner's own checkout.
        environment.systemPackages = with pkgs; [
          git
          gh
          cacert
        ];

        time.timeZone = "Asia/Jakarta";
        i18n.defaultLocale = "en_US.UTF-8";
        system.stateVersion = "25.11";
      };
  };

  # Container ordering + slice pin (single definition — merged):
  #  * start AFTER sops decrypts the PAT (the bindMount hostPath only exists once
  #    sops-install-secrets has run);
  #  * pin into the dedicated boxes-ci.slice, overriding nixos-containers.nix's
  #    default Slice = machine.slice.
  systemd.services."container@${name}" = {
    after = [ "sops-install-secrets.service" ];
    wants = [ "sops-install-secrets.service" ];
    serviceConfig.Slice = lib.mkForce "boxes-ci.slice";
  };

  # ── CPU/memory containment (decided: own dedicated slice) ────────────────────
  # nspawn boxes run as root-level container@<name>.service, OUTSIDE user.slice's
  # 680% ceiling — so, like the office boxes, they need an explicit quota. CI gets
  # its OWN top-level slice (NOT a child of the office boxes.slice) so a heavy
  # `docker build` never steals the office boxes' 400%. CPUQuota=400% ceiling +
  # batch-tier CPUWeight=10 so under host-wide contention CI yields to coding/
  # interactive/office work (host is intentionally oversubscribed; weights
  # arbitrate, quotas only cap). MemoryHigh soft-throttle, no hard MemoryMax
  # (mirrors the office boxes / media-batch policy).
  systemd.slices."boxes-ci".sliceConfig = {
    CPUQuota = "400%";
    CPUWeight = "10";
    MemoryHigh = "8G"; # TODO(tune): observe real CI peak via below/Grafana
  };
}
# ─────────────────────────────────────────────────────────────────────────────
# ONE-TIME SETUP (run on the host as homeserver)
#
# 1. Mint the fine-grained PAT (needs a browser; gh opens it). Scope it to
#    tigorlazuardi/ring-road ONLY, permissions: Administration = Read+Write
#    (runner registration), Actions = Read+Write. Copy the token (ghp_.../github_pat_...).
#       → https://github.com/settings/personal-access-tokens/new
#    (gh has no non-interactive fine-grained-PAT create; mint in the browser.)
#
# 2. Add it to sops (creates/edits the encrypted file):
#       cd ~/homelab
#       sops secrets/ring-road-ci.yaml
#    then add a line:   runner_pat: github_pat_xxxxxxxx
#
# 3. Rebuild:  sudo nixos-rebuild switch --flake ~/homelab#homeserver
#
# 4. Verify the runner registered:
#       gh api repos/tigorlazuardi/ring-road/actions/runners --jq '.runners[].name'
#    (expect: ring-road-ci-nspawn, status online)
#
# 5. In a workflow, target it:   runs-on: [self-hosted, nspawn, bun]
#
# VALIDATE-LIVE (single known risk, same posture as the office boxes' SPEC):
#   Rootless podman inside nspawn. If `docker`/`podman` in a job fails to reach the
#   socket, shell in and check the user socket exists:
#       sudo machinectl shell ci@ring-road-ci /bin/sh -c \
#         'systemctl --user status podman.socket; ls -l $XDG_RUNTIME_DIR/podman'
#   Fixes, in order of preference: (a) `systemctl --user enable --now podman.socket`
#   as ci; (b) if rootless refuses under nspawn, flip virtualisation.podman to the
#   rootful dockerSocket and drop DOCKER_HOST (nspawn is still the host-isolation
#   boundary, so rootful-in-guest does not pollute the host).
