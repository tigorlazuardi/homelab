{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    nil
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nixpkgs.config.allowUnfree = true;
}
