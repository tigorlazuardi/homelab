{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    bat
    eza
  ];
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting # Disable greeting

      # fzf fish keybindings: ctrl-t (files), ctrl-r (history), alt-c (cd).
      ${pkgs.fzf}/bin/fzf --fish | source

      # Run a command as the srv user (owns all rootless containers). Wraps the
      # `cd /tmp` gotcha (srv can't chdir into homeserver's 0700 home) + sets the
      # user-bus XDG_RUNTIME_DIR. Needs the NOPASSWD runAs=srv sudoers rule
      # (modules/users.nix). Usage: `srv podman ps`, `srv systemctl --user status wallrus`.
      function srv --description 'Run a command as the srv user from /tmp'
        pushd /tmp
        sudo -u srv XDG_RUNTIME_DIR=/run/user/1001 $argv
        set -l rc $status
        popd
        return $rc
      end
    '';
    shellAliases = {
      ls = "eza -la";
      cat = "bat";
    };
  };
  programs.zoxide = {
    enable = true;
    flags = [
      "--cmd cd"
      "--hook prompt"
    ];
  };
}
