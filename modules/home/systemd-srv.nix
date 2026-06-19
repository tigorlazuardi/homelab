# Fish helpers for talking to the `srv` service user's systemd --user instance
# (all rootless app containers run there). Actions go through sudo; log reads use
# the system journal directly (homeserver is in systemd-journal → no sudo).
{
  programs.fish.functions = {
    # Raw passthrough: `srvctl restart immich`, `srvctl list-units` ...
    srvctl = ''
      sudo -u srv XDG_RUNTIME_DIR=/run/user/(id -u srv) systemctl --user $argv
    '';

    # Read a unit's log (no sudo). Usage: `srvlog jellyfin`, `srvlog dex -f`,
    # `srvlog immich-server -n 50`. Extra args pass through to journalctl.
    srvlog = ''
      if test (count $argv) -eq 0
        echo "usage: srvlog <unit> [journalctl args]" >&2; return 2
      end
      set -l unit (string replace -r '\\.service$' "" $argv[1])
      journalctl _SYSTEMD_USER_UNIT=$unit.service _UID=(id -u srv) --no-pager $argv[2..-1]
    '';

    # Convenience wrappers (take a unit name).
    srvst = "srvctl status $argv";
    srvre = "srvctl restart $argv";
    srvstart = "srvctl start $argv";
    srvstop = "srvctl stop $argv";
    srvfix = "srvctl reset-failed $argv"; # clear a failed/start-limit unit

    # No-arg overviews.
    srvls = "srvctl list-units --type=service $argv";
    srvfail = "srvctl list-units --type=service --state=failed $argv";

    # Quick HTTP health of a loopback port: `srvping 8096`
    srvping = ''
      curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://127.0.0.1:$argv[1]/
    '';
  };
}
