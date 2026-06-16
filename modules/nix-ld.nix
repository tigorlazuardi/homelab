{ pkgs, ... }:
{
  # nix-ld: Run unpatched dynamic binaries (e.g. downloaded binaries, VSCode extensions)
  programs.nix-ld.enable = true;

  # envfs: Provides /usr/bin/env and other paths expected by scripts
  services.envfs.enable = true;

  # AppImage support
  programs.appimage = {
    enable = true;
    binfmt = true;
  };
}
