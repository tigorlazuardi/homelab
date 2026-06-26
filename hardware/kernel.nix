{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [
    "vmd"
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/var/mnt/nas" = {
    label = "WD_RED_4T_1";
    fsType = "ext4";
    # nas is a dying disk (failing SMART) holding only disposable downloads. Fail
    # soft: a dead/slow nas must not block boot or drop the headless host to
    # emergency mode (= remote lockout). nofail + a short device-timeout keep the
    # host booting and reachable so we can intervene.
    options = [ "nofail" "x-systemd.device-timeout=10s" ];
  };

  fileSystems."/var/mnt/wolf" = {
    label = "WOLF_4T_1";
    fsType = "ext4";
    # Data-only HDD (bulk media + arr downloads). A dead/slow wolf must never block
    # boot or drop the headless host to emergency mode (= remote lockout) — fail
    # soft like nas so the host stays reachable to intervene. Data is replaceable.
    options = [ "nofail" "x-systemd.device-timeout=10s" ];
  };

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.enableRedistributableFirmware = true;
  hardware.graphics.enable = true;
  hardware.graphics.extraPackages = with pkgs; [
    vpl-gpu-rt
    libvdpau-va-gl
  ];
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
  };

  # Allow disks to spin down.
  services.udev.extraRules =
    let
      mkRule = as: lib.concatStringsSep ", " as;
      mkRules = rs: lib.concatStringsSep "\n" rs;
    in
    mkRules [
      (mkRule [
        ''ACTION=="add|change"''
        ''SUBSYSTEM=="block"''
        ''KERNEL=="sd[a-z]"''
        ''ATTR{queue/rotational}=="1"''
        ''RUN+="${pkgs.hdparm}/bin/hdparm -B 90 -S 41 /dev/%k"''
      ])
    ];
}
