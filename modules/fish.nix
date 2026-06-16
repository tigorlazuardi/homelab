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
