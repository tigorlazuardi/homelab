{ pkgs, lib, ... }:
{
  boot = {
    loader = {
      systemd-boot = {
        enable = lib.mkDefault true;
        configurationLimit = 50;
        extraFiles = {
          # Disable the boot menu unless the user holds down a key
          "loader/loader.conf" = pkgs.writeText "loader.conf" ''
            timeout 0
          '';
        };
      };
      efi.canTouchEfiVariables = true;
    };
    tmp.cleanOnBoot = true;
  };
}
