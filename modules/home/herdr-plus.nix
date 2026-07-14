# herdr-plus: the cloudmanic/herdr-plus plugin (Projects + Quick Actions),
# packaged declaratively and linked into the running herdr daemon.
#
# WHY this shape (least-hacky): herdr plugins are normally installed imperatively
# with `herdr plugin install owner/repo`, which clones the repo, runs its
# [[build]] step, and records a MANAGED entry in ~/.config/herdr/plugins.json —
# state herdr owns (with resolved_commit + timestamps) that we must not hand-edit.
# Instead we:
#   1. build herdr-plus as a normal Nix package (buildGoModule) → an immutable
#      /nix/store path laid out as a herdr plugin dir (herdr-plugin.toml at the
#      root + bin/herdr-plus), with the manifest's [[build]] step stripped since
#      Nix already produced the binary (herdr must never try to run build.sh
#      against the read-only store path);
#   2. register it with the daemon via the official `herdr plugin link <path>`
#      mechanism (source.kind = "local"), driven idempotently by a systemd --user
#      oneshot. On every switch the unit re-points herdr at the CURRENT store
#      path, so a version bump (below) re-links automatically.
#
# Bump: update `version` + `srcHash`, then refresh `vendorHash` (set it to
# lib.fakeHash, build once, copy the "got:" hash from the error).
{
  pkgs,
  lib,
  config,
  ...
}:
let
  home = config.home.homeDirectory;
  herdr = config.programs.herdr.package;

  version = "0.1.16";
  srcHash = "sha256-WWu83LMBB9V0OFF1g4qmIkoTqOgXgWeNynv4Fk84xas=";
  vendorHash = "sha256-im2gPhLarMf1w/8rhxbOe9EhUdvseffukT9tqU4EEXI=";

  herdr-plus = pkgs.buildGoModule {
    pname = "herdr-plus";
    inherit version vendorHash;
    src = pkgs.fetchFromGitHub {
      owner = "cloudmanic";
      repo = "herdr-plus";
      rev = "v${version}";
      hash = srcHash;
    };

    ldflags = [
      "-s"
      "-w"
    ];

    # TestIsInsideGitWorkTree asserts the CWD is NOT inside a git worktree, but the
    # nix build sandbox (/build/...) trips git's discovery and the test fails
    # spuriously. Skip only that env-dependent test; keep the rest of the suite.
    checkFlags = [ "-skip=TestIsInsideGitWorkTree" ];

    # Lay $out out as a herdr plugin dir. buildGoModule already installs the binary
    # to $out/bin/herdr-plus (the manifest invokes "./bin/herdr-plus" relative to
    # the plugin root). Copy the manifest to the root with its [[build]] step
    # stripped — the binary is prebuilt, so link must not shell out to build.sh.
    postInstall = ''
      awk '
        /^\[\[build\]\]/ { skip=1; next }
        skip && /^command = / { skip=0; next }
        { print }
      ' herdr-plugin.toml > $out/herdr-plugin.toml
    '';

    meta = {
      description = "First-class herdr plugin — Projects + Quick Actions";
      homepage = "https://github.com/cloudmanic/herdr-plus";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
      mainProgram = "herdr-plus";
    };
  };

  pluginId = "cloudmanic.herdr-plus";

  # Idempotent link: re-point the daemon at the current store path only when it
  # differs from what's already registered (a version bump changes the path).
  # `herdr plugin link` on an unchanged path is itself idempotent, but the guard
  # keeps the switch quiet and handles the path-changed case with an unlink first.
  link = pkgs.writeShellScript "herdr-plus-link" ''
    set -u
    export PATH="${
      lib.makeBinPath [
        herdr
        pkgs.jq
        pkgs.coreutils
      ]
    }:$PATH"
    want="${herdr-plus}"

    # Wait for the daemon to accept commands (Type=simple server may lag its unit).
    up() { herdr status server 2>/dev/null | grep -q '^status: running'; }
    for _ in $(seq 1 30); do up && break; sleep 1; done
    if ! up; then echo "herdr server never became ready" >&2; exit 1; fi

    current=$(herdr plugin list --json 2>/dev/null \
      | jq -r --arg id "${pluginId}" \
          '.result.plugins[]? | select(.plugin_id==$id) | .plugin_root' || true)

    if [ "$current" = "$want" ]; then
      echo "herdr-plus already linked at $want — skip"
      exit 0
    fi
    if [ -n "$current" ]; then
      echo "herdr-plus linked at stale $current — unlinking"
      herdr plugin unlink "${pluginId}" || true
    fi
    echo "linking herdr-plus -> $want"
    herdr plugin link "$want"
  '';
in
{
  # Put the binary on PATH too, so `herdr-plus version` and the Homebrew-style CLI
  # work in a shell (the plugin entry points use the store bin regardless).
  home.packages = [ herdr-plus ];

  systemd.user.services.herdr-plus-link = {
    Unit = {
      Description = "Link the herdr-plus plugin into the herdr daemon";
      After = [ "herdr-server.service" ];
      Requires = [ "herdr-server.service" ];
      # Re-link whenever the server restarts (a restart reloads the registry).
      PartOf = [ "herdr-server.service" ];
    };
    Install.WantedBy = [ "default.target" ];
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${link}";
      WorkingDirectory = home;
      Slice = "sessions.slice";
    };
  };
}
