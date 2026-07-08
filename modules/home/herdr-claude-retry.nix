# herdr-claude-retry: watches every claude pane in herdr, detects the Anthropic
# rate-limit banner (screen regex + usage-API cross-check) and injects `continue`
# once the limit clears. This closes the healing gap noted in herdr-sessions.nix
# ("claude dead inside a pane that survived a native restore").
#
# Runs as a systemd --user daemon instead of inside a herdr pane: nothing to
# exclude (it only skips its OWN pane when it has one), and systemd gives us
# Restart=always + slice accounting for free.
#
# Packaging: the npm tarball ships a prebuilt dist/ and has ZERO runtime deps,
# so no buildNpmPackage/npmDepsHash ceremony — fetch, unpack, run with node.
# Bump: update `version` + `hash` (nix store prefetch-file <tarball-url>).
# NB: the package's bin name is literally `herdr` (collides with the real herdr
# binary) — deliberately NOT installed into home.packages; only this unit runs it.
{
  pkgs,
  config,
  ...
}:
let
  home = config.home.homeDirectory;

  version = "0.1.7";
  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@tigorhutasuhut/herdr-claude-retry/-/herdr-claude-retry-${version}.tgz";
    hash = "sha256-h4xv72wgGDkN3p+LRJQUQ9MFx0TbLik9Kgr6t656dGM=";
  };

  herdr-claude-retry = pkgs.stdenvNoCC.mkDerivation {
    pname = "herdr-claude-retry";
    inherit version src;
    installPhase = ''
      mkdir -p $out/lib
      cp -r . $out/lib
    '';
  };
in
{
  systemd.user.services.herdr-claude-retry = {
    Unit = {
      Description = "Auto-resume rate-limited claude panes in herdr";
      # Needs the herdr socket; restart of the daemon invalidates our event
      # subscriptions, so PartOf ties our lifecycle to the server's.
      After = [ "herdr-server.service" ];
      Requires = [ "herdr-server.service" ];
      PartOf = [ "herdr-server.service" ];
    };
    Install.WantedBy = [ "default.target" ];
    Service = {
      Type = "simple";
      # Default socket path (~/.config/herdr/herdr.sock) matches our herdr
      # setup; usage-API detection resolves CLAUDE_CONFIG_DIR from each claude
      # process's /proc environment (same uid), no env needed here.
      ExecStart = "${pkgs.nodejs}/bin/node ${herdr-claude-retry}/lib/dist/cli.js start";
      WorkingDirectory = home;
      Slice = "sessions.slice";
      Restart = "always";
      RestartSec = 5;
    };
  };
}
