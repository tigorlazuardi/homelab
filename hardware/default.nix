{ lib, ... }:
{
  imports = [
    ./disko.nix
    ./kernel.nix
  ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}

